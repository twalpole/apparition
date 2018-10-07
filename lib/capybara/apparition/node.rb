# frozen_string_literal: true

require 'ostruct'
module Capybara::Apparition
  class Node < Capybara::Driver::Node
    attr_reader :page_id

    def initialize(driver, page, remote_object)
      super(driver, self)
      @page = page
      # @page_id = page_id
      @remote_object = remote_object
    end

    def id
      @remote_object
    end

    def browser
      driver.browser
    end

    def parents
      find('xpath', 'ancestor::*').reverse
    end

    def find(method, selector)
      results = if method == :css
        evaluate_on <<~JS, value: selector
          function(selector){
            return Array.from(this.querySelectorAll(selector));
          }
        JS
      else
        evaluate_on <<~JS, value: selector
          function(selector){
            const xpath = document.evaluate(selector, this, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
            let results = [];
            for (let i=0; i < xpath.snapshotLength; i++){
              results.push(xpath.snapshotItem(i));
            }
            return results;
          }
        JS
      end

      results.map { |r_o| Capybara::Apparition::Node.new(driver, @page, r_o['objectId']) }
    rescue ::Capybara::Apparition::BrowserError => e
      raise unless e.name =~ /is not a valid (XPath expression|selector)/

      raise Capybara::Apparition::InvalidSelector, [method, selector]
    end

    def find_xpath(selector)
      find :xpath, selector
    end

    def find_css(selector)
      find :css, selector
    end

    def all_text
      text = evaluate_on('function(){ return this.textContent }')
      text.to_s.gsub(/[\u200b\u200e\u200f]/, '')
               .gsub(/[\ \n\f\t\v\u2028\u2029]+/, ' ')
               .gsub(/\A[[:space:]&&[^\u00a0]]+/, '')
               .gsub(/[[:space:]&&[^\u00a0]]+\z/, '')
               .tr("\u00a0", ' ')
    end

    def visible_text
      return "" unless visible?

      text = evaluate_on <<~JS
        function(){
          if (this.nodeName == 'TEXTAREA'){
            return this.textContent;
          } else if (this instanceof SVGElement) {
            return this.textContent;
          } else {
            return this.innerText;
          }
        }
      JS
      text.to_s.gsub(/\A[[:space:]&&[^\u00a0]]+/, "")
               .gsub(/[[:space:]&&[^\u00a0]]+\z/, "")
               .gsub(/\n+/, "\n")
               .tr("\u00a0", " ")
    end

    def property(name)
      evaluate_on('function(name){ return this[name] }', value: name)
    end

    def attribute(name)
      if %w[checked selected].include?(name.to_s)
        property(name)
      else
        evaluate_on('function(name){ return this.getAttribute(name)}', value: name)
      end
    end

    def [](name)
      # Although the attribute matters, the property is consistent. Return that in
      # preference to the attribute for links and images.
      if ((tag_name == 'img') && (name == 'src')) || ((tag_name == 'a') && (name == 'href'))
        # if attribute exists get the property
        value = attribute(name) && property(name)
        return value
      end

      value = property(name)
      value = attribute(name) if value.nil? || value.is_a?(Hash)

      value
    end

    def attributes
      evaluate_on <<~JS
        function(){
          let attrs = {};
          for (let attr of this.attributes)
            attrs[attr.name] = attr.value.replace("\n","\\n");
          return attrs;
        }
      JS
    end

    def value
      evaluate_on <<~JS
        function(){
          if ((this.tagName == 'SELECT') && this.multiple){
            console.log('multiple');
            let selected = [];
            for (let option of this.children) {
              if (option.selected) {
                selected.push(option.value);
              }
            }
            return selected;
          } else {
            return this.value;
          }
        }
      JS
    end

    def set(value, **_options)
      if tag_name == 'input'
        case self[:type]
        when 'radio'
          click
        when 'checkbox'
          click if value != checked?
        when 'file'
          files = value.respond_to?(:to_ary) ? value.to_ary.map(&:to_s) : value.to_s
          set_files(files)
        when 'date'
          set_date(value)
        when 'time'
          set_time(value)
        when 'datetime-local'
          set_datetime_local(value)
        else
          set_text(value.to_s)
        end
      elsif tag_name == 'textarea'
        set_text(value.to_s)
      elsif self[:isContentEditable]
        delete_text
        send_keys(value.to_s)
      end
    end

    def select_option
      return false if disabled?

      evaluate_on <<~JS
        function(){
          let sel = this.parentNode;
          if (sel.tagName == 'OPTGROUP'){
            sel = sel.parentNode;
          }
          let event_options = { bubbles: true, cancelable: true };
          sel.dispatchEvent(new FocusEvent('focus', event_options));

          this.selected = true

          sel.dispatchEvent(new Event('change', event_options));
          sel.dispatchEvent(new FocusEvent('blur', event_options));

        }
      JS
      true
    end

    def unselect_option
      return false if disabled?

      res = evaluate_on <<~JS
        function(){
          let sel = this.parentNode;
          if (sel.tagName == 'OPTGROUP') {
            sel = sel.parentNode;
          }

          if (!sel.multiple){
            return false;
          }

          // window.__apparition.trigger('focus', sel);
          this.selected = false;
          // window.__apparition.changed(this);
          // window.__apparition.trigger('blur', sel);
          return true;
        }
      JS
      res || raise(Capybara::UnselectNotAllowed, 'Cannot unselect option from single select box.')
    end

    def tag_name
      @tag_name ||= evaluate_on('function(){ return this.tagName; }').downcase
    end

    def visible?
      # if an area element, check visibility of relevant image
      evaluate_on <<~JS
        function(){
          el = this;
          if (el.tagName == 'AREA'){
            const map_name = document.evaluate('./ancestor::map/@name', el, null, XPathResult.STRING_TYPE, null).stringValue;
            el = document.querySelector(`img[usemap='#${map_name}']`);
            if (!el){
             return false;
            }
          }

          while (el) {
            const style = window.getComputedStyle(el);
            if ((style.display == 'none') ||
                (style.visibility == 'hidden') ||
                (parseFloat(style.opacity) == 0)) {
              return false;
            }
            el = el.parentElement;
          }
          return true;
        }
      JS
    end

    def checked?
      self[:checked]
    end

    def selected?
      !!self[:selected]
    end

    def disabled?
      evaluate_on <<~JS
        function() {
          const xpath = 'parent::optgroup[@disabled] | \
                         ancestor::select[@disabled] | \
                         parent::fieldset[@disabled] | \
                         ancestor::*[not(self::legend) or preceding-sibling::legend][parent::fieldset[@disabled]]';
          return this.disabled || document.evaluate(xpath, this, null, XPathResult.BOOLEAN_TYPE, null).booleanValue
        }
      JS
    end

    def click(keys = [], button: 'left', count: 1, **options)
      pos = if (options[:x] && options[:y])
        visible_top_left.tap do |p|
          p[:x] += options[:x]
          p[:y] += options[:y]
        end
      else
        visible_center
      end
      raise ::Capybara::Apparition::MouseEventImpossible.new(self, 'args' => ['click']) if pos.nil?

      raise ::Capybara::Apparition::MouseEventFailed.new(self, 'args' => ['click', test['selector'], pos]) unless mouse_event_test?(pos)

      @page.mouse.click_at pos.merge(button: button, count: count, modifiers: keys)
      puts 'Waiting to see if click triggered page load' if ENV['DEBUG']
      sleep 0.1
      return unless @page.current_state == :loading

      puts 'Waiting for page load' if ENV['DEBUG']
      while @page.current_state != :loaded
        sleep 0.05
        puts "current_state is #{@page.current_state}"
      end
    end

    def right_click(keys = [], **_options)
      click(keys, button: 'right')
    end

    def double_click(keys = [], **_options)
      click(keys, count: 2)
    end

    def hover
      pos = visible_center
      raise ::Capybara::Apparition::MouseEventImpossible.new(self, 'args' => ['hover']) if pos.nil?

      @page.mouse.move_to(pos)
    end

    def drag_to(other, delay: 0.1)
      pos = visible_center
      raise ::Capybara::Apparition::MouseEventImpossible.new(self, 'args' => ['drag_to']) if pos.nil?

      other_pos = other.visible_center
      raise ::Capybara::Apparition::MouseEventImpossible.new(self, 'args' => ['drag_to']) if other_pos.nil?
      raise ::Capybara::Apparition::MouseEventFailed.new(self, 'args' => ['drag', test['selector'], pos]) unless mouse_event_test?(pos)

      @page.mouse.move_to(pos)
      @page.mouse.down(pos)
      sleep delay
      @page.mouse.move_to(other_pos.merge(button: 'left'))
      sleep delay
      @page.mouse.up(other_pos)
    end

    def drag_by(x, y, delay: 0.1)
      pos = visible_center
      raise ::Capybara::Apparition::MouseEventImpossible.new(self, 'args' => ['hover']) if pos.nil?

      other_pos = { x: pos[:x] + x, y: pos[:y] + y }
      raise ::Capybara::Apparition::MouseEventFailed.new(self, 'args' => ['drag', test['selector'], pos]) unless mouse_event_test?(pos)

      @page.mouse.move_to(pos)
      @page.mouse.down(pos)
      sleep delay
      @page.mouse.move_to(other_pos.merge(button: 'left'))
      sleep delay
      @page.mouse.up(other_pos)
    end

    EVENTS = {
      blur: ['FocusEvent'],
      focus: ['FocusEvent'],
      focusin: ['FocusEvent', { bubbles: true  }],
      focusout: ['FocusEvent', { bubbles: true }],
      click: ['MouseEvent', { bubbles: true, cancelable: true }],
      dblckick: ['MouseEvent', { bubbles: true, cancelable: true }],
      mousedown: ['MouseEvent', { bubbles: true, cancelable: true }],
      mouseup: ['MouseEvent', { bubbles: true, cancelable: true }],
      mouseenter: ['MouseEvent'],
      mouseleave: ['MouseEvent'],
      mousemove: ['MouseEvent', { bubbles: true, cancelable: true }],
      submit: ['Event', { bubbles: true, cancelable: true }]
    }.freeze

    def trigger(name, **options)
      raise ArgumentError, 'Unknown event' unless EVENTS.key?(name.to_sym)

      event_type, opts = EVENTS[name.to_sym]
      opts ||= {}

      evaluate_on <<~JS, { value: name }, value: opts.merge(options)
        function(name, options){
          var event = new #{event_type}(name, options);
          this.dispatchEvent(event);
        }
      JS
    end

    def ==(other)
      evaluate_on('function(el){ return this == el; }', objectId: other.id)
    rescue ObsoleteNode
      false
    end

    def send_keys(*keys)
      selected = evaluate_on <<~JS
        function(){
          let selectedNode = document.getSelection().focusNode;
          if (!selectedNode)
            return false;
          if (selectedNode.nodeType == 3)
            selectedNode = selectedNode.parentNode;
          return this.contains(selectedNode);
        }
      JS
      click unless selected
      @page.keyboard.type(keys)
    end
    alias_method :send_key, :send_keys

    def path
      evaluate_on <<~JS
        function(){
          const xpath = document.evaluate('ancestor-or-self::node()', this, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
          let elements = [];
          for (let i=1; i<xpath.snapshotLength; i++){
            elements.push(xpath.snapshotItem(i));
          }
          let selectors = elements.map( el => {
            prev_siblings = document.evaluate(`./preceding-sibling::${el.tagName}`, el, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
            return `${el.tagName}[${prev_siblings.snapshotLength + 1}]`;
          })
          return '//' + selectors.join('/');
        }
      JS
    end

    def visible_top_left
      evaluate_on('function(){ this.scrollIntoViewIfNeeded() }')
      # result = @page.command('DOM.getBoxModel', objectId: id)
      result = evaluate_on <<~JS
        function(){
          var rect = this.getBoundingClientRect();
          return rect.toJSON();
        }
      JS

      return nil if result.nil?

      result = result['model'] if result['model']
      frame_offset = @page.current_frame_offset

      lm = @page.command('Page.getLayoutMetrics')
      if (result['width'].zero? || result['height'].zero?) && (tag_name == 'area')
        map = find('xpath', 'ancestor::map').first
        img = find('xpath', "//img[@usemap='##{map[:name]}']").first
        return nil unless img.visible?

        img_pos = img.top_left
        coords = self[:coords].split(',').map(&:to_i)

        offset_pos = case self[:shape]
        when 'rect'
          { x: coords[0], y: coords[1] }
        when 'circle'
          { x: coords[0], y: coords[1] }
        when 'poly'
          raise 'TODO: Poly not implemented'
        else
          raise 'Unknown Shape'
        end

        { x: img_pos[:x] + offset_pos[:x] + frame_offset[:x],
          y: img_pos[:y] + offset_pos[:y] + frame_offset[:y] }
      else
        { x: result['left'] + frame_offset[:x],
          y: result['top'] + frame_offset[:y] }
      end
    end

    def visible_center
      evaluate_on('function(){ this.scrollIntoViewIfNeeded() }')
      # result = @page.command('DOM.getBoxModel', objectId: id)
      result = evaluate_on <<~JS
        function(){
          var rect = this.getBoundingClientRect();
          return rect.toJSON();
        }
      JS

      return nil if result.nil?

      result = result['model'] if result['model']
      frame_offset = @page.current_frame_offset

      lm = @page.command('Page.getLayoutMetrics')
      if (result['width'].zero? || result['height'].zero?) && (tag_name == 'area')
        map = find('xpath', 'ancestor::map').first
        img = find('xpath', "//img[@usemap='##{map[:name]}']").first
        return nil unless img.visible?

        img_pos = img.top_left
        coords = self[:coords].split(',').map(&:to_i)

        offset_pos = case self[:shape]
        when 'rect'
          { x: (coords[0] + coords[2]) / 2,
            y: (coords[1] + coords[2]) / 2 }
        when 'circle'
          { x: coords[0], y: coords[1] }
        when 'poly'
          raise 'TODO: Poly not implemented'
        else
          raise 'Unknown Shape'
        end

        { x: img_pos[:x] + offset_pos[:x] + frame_offset[:x],
          y: img_pos[:y] + offset_pos[:y] + frame_offset[:y] }
      else
        # quad = result["border"]
        # xs,ys = quad.partition.with_index { |_, idx| idx.even? }
        xs = [result['left'], result['right']]
        ys = [result['top'], result['bottom']]
        x_extents, y_extents = xs.minmax, ys.minmax

        x_extents[1] = [x_extents[1], lm['layoutViewport']['clientWidth']].min
        y_extents[1] = [y_extents[1], lm['layoutViewport']['clientHeight']].min

        { x: (x_extents.sum / 2) + frame_offset[:x],
          y: (y_extents.sum / 2) + frame_offset[:y] }
      end
    end

    def top_left
      result = evaluate_on <<~JS
        function(){
          rect = this.getBoundingClientRect();
          return rect.toJSON();
        }
      JS
      # @page.command('DOM.getBoxModel', objectId: id)
      return nil if result.nil?

      # { x: result["model"]["content"][0],
      #   y: result["model"]["content"][1] }
      { x: result['x'],
        y: result['y'] }
    end

  private

    def filter_text(text)
      text.to_s.gsub(/[[:space:]]+/, ' ').strip
    end

    def evaluate_on(page_function, *args)
      obsolete_checked_function = <<~JS
        function(){
          console.log(this);
          if (!this.ownerDocument.contains(this)) { throw 'ObsoleteNode' };
          return #{page_function.strip}.apply(this, arguments);
        }
      JS
      response = @page.command('Runtime.callFunctionOn',
                               functionDeclaration: obsolete_checked_function,
                               objectId: id,
                               returnByValue: false,
                               awaitPromise: true,
                               arguments: args)
      process_response(response)
    end

    def process_response(response)
      exception_details = response['exceptionDetails']
      if exception_details && (exception = exception_details['exception'])
        case exception['className']
        when 'DOMException'
          raise ::Capybara::Apparition::BrowserError.new('name' => exception['description'], 'args' => nil)
        else
          raise ::Capybara::Apparition::ObsoleteNode.new(self, '') if exception['value'] == 'ObsoleteNode'

          puts "Unknown Exception: #{exception['value']}"
        end
        raise exception_details
      end

      result = response['result'] || response ['object']
      if result['type'] == 'object'
        if result['subtype'] == 'array'
          remote_object = @page.command('Runtime.getProperties',
                                        objectId: result['objectId'],
                                        ownProperties: true)

          properties = remote_object['result']
          results = []

          properties.each do |property|
            if property['enumerable']
              if property['value']['subtype'] == 'node'
                results.push(property['value'])
              else
                #     releasePromises.push(helper.releaseObject(@element._client, property.value))
                results.push(property['value']['value'])
              end
            end
            # await Promise.all(releasePromises);
            # id = (@page._elements.push(element)-1 for element from result)[0]
            #
            # new Apparition.Node @page, id

            # releasePromises = [helper.releaseObject(@element._client, remote_object)]
          end

          return results
          { 'type' => 'object', 'subtype' => 'node', 'className' => 'HTMLParagraphElement', 'description' => 'p#change', 'objectId' => '{"injectedScriptId":6885,"id":1}' }
        elsif result['subtype'] == 'node'
          return result
        elsif result['className'] == 'Object'
          remote_object = @page.command('Runtime.getProperties',
                                        objectId: result['objectId'],
                                        ownProperties: true)
          properties = remote_object['result']

          properties.each_with_object({}) do |property, memo|
            if property['enumerable']
              memo[property['name']] = property['value']['value']
            else
              #     releasePromises.push(helper.releaseObject(@element._client, property.value))
            end
            # releasePromises = [helper.releaseObject(@element._client, remote_object)]
          end
        else
          result['value']
        end
      else
        result['value']
      end
    end

    def set_text(value)
      return if evaluate_on('function(){ return this.readOnly }')

      max_length = evaluate_on('function(){ return this.maxLength }')
      value = value.slice(0, max_length) if max_length >= 0
      evaluate_on <<~JS
        function() {
          this.focus();
          this.value = '';
        }
      JS
      if %w[number date].include?(self['type'])
        evaluate_on('function(value){ this.value = value; }', value: value)
      else
        @page.keyboard.type(value)
      end
      evaluate_on('function(){ this.blur(); }')
    end

    def set_files(files)
      @page.command('DOM.setFileInputFiles',
                    files: Array(files),
                    objectId: id)
    end

    def set_date(value)
      value = SettableValue.new(value)
      return set_text(value) unless value.dateable?

      # TODO: this would be better if locale can be detected and correct keystrokes sent
      update_value_js(value.to_date_str)
    end

    def set_time(value)
      value = SettableValue.new(value)
      return set_text(value) unless value.timeable?

      # TODO: this would be better if locale can be detected and correct keystrokes sent
      update_value_js(value.to_time_str)
    end

    def set_datetime_local(value)
      value = SettableValue.new(value)
      return set_text(value) unless value.timeable?

      # TODO: this would be better if locale can be detected and correct keystrokes sent
      update_value_js(value.to_datetime_str)
    end

    def update_value_js(value)
      evaluate_on(<<~JS, value: value)
        function(value){
          if (document.activeElement !== this){
            this.focus();
          }
          if (this.value != value) {
            this.value = value;
            this.dispatchEvent(new InputEvent('input'));
            this.dispatchEvent(new Event('change', { bubbles: true }));
          }
        }
      JS
    end

    def mouse_event_test?(x:, y:)
      mouse_event_test(x: x, y: y)['status'] == 'success'
    end

    def mouse_event_test(x:, y:)
      frame_offset = @page.current_frame_offset
      # return { status: 'failure' } if x < 0 || y < 0
      evaluate_on(<<~JS, { value: x - frame_offset[:x] }, value: y - frame_offset[:y])
        function(x,y){
          const hit_node = document.elementFromPoint(x,y);
          if ((hit_node == this) || this.contains(hit_node))
            return { status: 'success' };

          console.log(hit_node);
          const getSelector = function(element){
            if (element == null)
              return 'Element out of bounds';

            let selector = '';
            if (element.tagName != 'HTML')
              selector = getSelector(element.parentNode) + ' ';
            selector += element.tagName.toLowerCase();
            if (element.id)
              selector += `#${element.id}`;

            for (let className of element.classList){
              if (className != '')
                selector += `.${className}`;
            }
            return selector;
          }

          return { status: 'failure', selector: getSelector(hit_node) };
        }
      JS
    end

    #   evaluate_on("function(hit_node){
    #     if ((this == hit_node) || (this.contains(hit_node)))
    #       return { status: 'success' };
    #
    #     const getSelector = function(element){
    #       console.log(element);
    #       let selector = '';
    #       if (element.tagName != 'HTML')
    #         selector = getSelector(element.parentNode) + ' ';
    #       selector += element.tagName.toLowerCase();
    #       if (element.id)
    #         selector += `#${element.id}`;
    #
    #       for (let className of element.classList){
    #         if (className != '')
    #           selector += `.${className}`;
    #       }
    #       return selector;
    #     }
    #
    #     return { status: 'failure', selector: getSelector(hit_node)};
    #   }", objectId: hit_node_id)

    # def mouse_event_test(x:, y:)
    #   return { status: 'failure' } if x < 0 || y < 0
    #   # TODO Fix this
    #   # puts "Defaulting mouse_event_test to true for now" if ENV['DEBUG']
    #   # return { 'status' => 'success'}
    #
    #   response = @page.command('DOM.getNodeForLocation', x: x.to_i, y: y.to_i)
    #   response = @page.command('DOM.resolveNode', nodeId: response["nodeId"])
    #   hit_node_id = response["object"]["objectId"]
    #
    #   evaluate_on("function(hit_node){
    #     if ((this == hit_node) || (this.contains(hit_node)))
    #       return { status: 'success' };
    #
    #     const getSelector = function(element){
    #       console.log(element);
    #       let selector = '';
    #       if (element.tagName != 'HTML')
    #         selector = getSelector(element.parentNode) + ' ';
    #       selector += element.tagName.toLowerCase();
    #       if (element.id)
    #         selector += `#${element.id}`;
    #
    #       for (let className of element.classList){
    #         if (className != '')
    #           selector += `.${className}`;
    #       }
    #       return selector;
    #     }
    #
    #     return { status: 'failure', selector: getSelector(hit_node)};
    #   }", objectId: hit_node_id)
    # end

    def delete_text
      evaluate_on <<~JS
        function(){
          range = document.createRange();
          range.selectNodeContents(this);
          window.getSelection().removeAllRanges();
          window.getSelection().addRange(range);
          window.getSelection().deleteFromDocument();
          window.getSelection().removeAllRanges();
        }
      JS
    end

    # SettableValue encapsulates time/date field formatting
    class SettableValue
      attr_reader :value

      def initialize(value)
        @value = value
      end

      def to_s
        value.to_s
      end

      def dateable?
        !value.is_a?(String) && value.respond_to?(:to_date)
      end

      def to_date_str
        value.to_date.strftime('%Y-%m-%d')
      end

      def timeable?
        !value.is_a?(String) && value.respond_to?(:to_time)
      end

      def to_time_str
        value.to_time.strftime('%H:%M')
      end

      def to_datetime_str
        value.to_time.strftime('%Y-%m-%dT%H:%M')
      end
    end
    private_constant :SettableValue
  end
end
