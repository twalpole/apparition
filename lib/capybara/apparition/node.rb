# frozen_string_literal: true

require 'ostruct'
module Capybara::Apparition
  class Node < Capybara::Driver::Node
    attr_reader :page_id

    def initialize(driver, page, remote_object)
      super(driver, self)
      @page = page
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
      js = method == :css ? FIND_CSS_JS : FIND_XPATH_JS
      evaluate_on(js, value: selector).map do |r_o|
        Capybara::Apparition::Node.new(driver, @page, r_o['objectId'])
      end
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
      return '' unless visible?

      text = evaluate_on ELEMENT_VISIBLE_TEXT_JS
      text.to_s.gsub(/\A[[:space:]&&[^\u00a0]]+/, '')
          .gsub(/[[:space:]&&[^\u00a0]]+\z/, '')
          .gsub(/\n+/, "\n")
          .tr("\u00a0", ' ')
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
      # return evaluate_on ELEMENT_PROP_OR_ATTR_JS, value: name
      # Although the attribute matters, the property is consistent. Return that in
      # preference to the attribute for links and images.
      if ((tag_name == 'img') && (name == 'src')) || ((tag_name == 'a') && (name == 'href'))
        # if attribute exists get the property
        return attribute(name) && property(name)
      end

      value = property(name)
      value = attribute(name) if value.nil? || value.is_a?(Hash)

      value

    end

    def attributes
      evaluate_on GET_ATTRIBUTES_JS
    end

    def value
      evaluate_on GET_VALUE_JS
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

      evaluate_on SELECT_OPTION_JS
      true
    end

    def unselect_option
      return false if disabled?

      evaluate_on(UNSELECT_OPTION_JS) ||
        raise(Capybara::UnselectNotAllowed, 'Cannot unselect option from single select box.')
    end

    def tag_name
      @tag_name ||= evaluate_on('function(){ return this.tagName; }').downcase
    end

    def visible?
      evaluate_on VISIBLE_JS
    end

    def checked?
      self[:checked]
    end

    def selected?
      !!self[:selected]
    end

    def disabled?
      evaluate_on ELEMENT_DISABLED_JS
    end

    def click(keys = [], button: 'left', count: 1, **options)
      pos = element_click_pos(options)
      raise ::Capybara::Apparition::MouseEventImpossible.new(self, 'args' => ['click']) if pos.nil?

      test = mouse_event_test(pos)
      raise ::Capybara::Apparition::MouseEventFailed.new(self, 'args' => ['click', test.selector, pos]) unless test.success

      @page.mouse.click_at pos.merge(button: button, count: count, modifiers: keys)
      if ENV['DEBUG']
        new_pos = element_click_pos(options)
        puts "Element moved from #{pos} to #{new_pos}" unless pos == new_pos
      end
      # Wait a short time to see if click triggers page load
      sleep 0.05
      @page.wait_for_loaded(allow_obsolete: true)
    end

    def right_click(keys = [], **options)
      click(keys, button: 'right', **options)
    end

    def double_click(keys = [], **options)
      click(keys, count: 2, **options)
    end

    def hover
      pos = visible_center
      raise ::Capybara::Apparition::MouseEventImpossible.new(self, 'args' => ['hover']) if pos.nil?

      @page.mouse.move_to(pos)
    end

    def drag_to(other, delay: 0.1)
      pos = visible_center
      raise ::Capybara::Apparition::MouseEventImpossible.new(self, 'args' => ['drag_to']) if pos.nil?

      test = mouse_event_test(pos)
      raise ::Capybara::Apparition::MouseEventFailed.new(self, 'args' => ['drag', test.selector, pos]) unless test.success

      begin
        @page.mouse.move_to(pos)
        @page.mouse.down(pos)
        sleep delay

        other_pos = other.visible_center
        raise ::Capybara::Apparition::MouseEventImpossible.new(self, 'args' => ['drag_to']) if other_pos.nil?

        @page.mouse.move_to(other_pos.merge(button: 'left'))
        sleep delay
      ensure
        @page.mouse.up(other_pos)
      end
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
      click unless evaluate_on(CURRENT_NODE_SELECTED_JS)
      @page.keyboard.type(keys)
    end
    alias_method :send_key, :send_keys

    def path
      evaluate_on GET_PATH_JS
    end

    def element_click_pos(x: nil, y: nil, **_)
      if x && y
        visible_top_left.tap do |p|
          p[:x] += x
          p[:y] += y
        end
      else
        visible_center
      end
    end

    def visible_top_left
      evaluate_on('function(){ this.scrollIntoViewIfNeeded() }')
      # result = @page.command('DOM.getBoxModel', objectId: id)
      result = evaluate_on GET_BOUNDING_CLIENT_RECT_JS
      return nil if result.nil?

      result = result['model'] if result['model']
      frame_offset = @page.current_frame_offset

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
      result = evaluate_on GET_BOUNDING_CLIENT_RECT_JS

      return nil if result.nil?

      result = result['model'] if result['model']
      frame_offset = @page.current_frame_offset

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
        lm = @page.command('Page.getLayoutMetrics')
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
      result = evaluate_on GET_BOUNDING_CLIENT_RECT_JS
      return nil if result.nil?

      { x: result['x'],
        y: result['y'] }
    end

    def scroll_by(x, y)
      evaluate_on <<~JS, { value: x }, value: y
        function(x, y){ this.scrollBy(x,y); }
      JS
    end

    def scroll_to(element, location, position = nil)
      # location, element = element, nil if element.is_a? Symbol
      if element.is_a? Capybara::Apparition::Node
        scroll_element_to_location(element, location)
      elsif location.is_a? Symbol
        scroll_to_location(location)
      else
        scroll_to_coords(*position)
      end
      self
    end

  protected

    def evaluate_on(page_function, *args)
      obsolete_checked_function = <<~JS
        function(){
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

  private

    def filter_text(text)
      text.to_s.gsub(/[[:space:]]+/, ' ').strip
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

          return extract_properties_array(remote_object['result'])
        elsif result['subtype'] == 'node'
          return result
        elsif result['className'] == 'Object'
          remote_object = @page.command('Runtime.getProperties',
                                        objectId: result['objectId'],
                                        ownProperties: true)
          extract_properties_object(remote_object['result'])
        else
          result['value']
        end
      else
        result['value']
      end
    end

    def set_text(value, clear: nil, **_unused)
      value = value.to_s
      if value.empty? && clear.nil?
        evaluate_on <<~JS
          function() {
            this.focus();
            this.value = '';
            this.dispatchEvent(new Event('change', { bubbles: true }));
          }
        JS
      elsif clear == :backspace
        # Clear field by sending the correct number of backspace keys.
        backspaces = [:backspace] * self.value.to_s.length
        send_keys(*([:end] + backspaces + [value]))
      elsif clear.is_a? Array
        send_keys(*clear, value)
      else
        # Clear field by JavaScript assignment of the value property.
        # Script can change a readonly element which user input cannot, so
        # don't execute if readonly.
        driver.execute_script "arguments[0].value = ''", self unless clear == :none
        send_keys(value)
      end
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
      mouse_event_test(x: x, y: y).success
    end

    def mouse_event_test(x:, y:)
      frame_offset = @page.current_frame_offset
      # return { status: 'failure' } if x < 0 || y < 0
      result = evaluate_on(<<~JS, { value: x - frame_offset[:x] }, value: y - frame_offset[:y])
        function(x,y){
          const hit_node = document.elementFromPoint(x,y);
          if ((hit_node == this) || this.contains(hit_node))
            return { status: 'success' };

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

      OpenStruct.new(success: result['status'] == 'success', selector: result['selector'])
    end

    def scroll_element_to_location(element, location)
      scroll_opts = case location
      when :top
        'true'
      when :bottom
        'false'
      when :center
        "{behavior: 'instant', block: 'center'}"
      else
        raise ArgumentError, "Invalid scroll_to location: #{location}"
      end
      element.evaluate_on "function(){ this.scrollIntoView(#{scroll_opts}) }"
    end

    def scroll_to_location(location)
      scroll_y = case location
      when :top
        '0'
      when :bottom
        'this.scrollHeight'
      when :center
        '(this.scrollHeight - this.clientHeight)/2'
      end
      evaluate_on "function(){ this.scrollTo(0, #{scroll_y}) }"
    end

    def scroll_to_coords(x, y)
      evaluate_on <<~JS, { value: x }, value: y
        function(x,y){ this.scrollTo(x,y) }
      JS
    end

    def delete_text
      evaluate_on DELETE_TEXT_JS
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

    def extract_properties_array(properties)
      properties.each_with_object([]) do |property, results|
        if property['enumerable']
          if property.dig('value', 'subtype') == 'node'
            results.push(property['value'])
          else
            #     releasePromises.push(helper.releaseObject(@element._client, property.value))
            results.push(property.dig('value', 'value'))
          end
        end
        # await Promise.all(releasePromises);
        # id = (@page._elements.push(element)-1 for element from result)[0]
        #
        # new Apparition.Node @page, id

        # releasePromises = [helper.releaseObject(@element._client, remote_object)]
      end
    end

    def extract_properties_object(properties)
      properties.each_with_object({}) do |property, object|
        if property['enumerable']
          object[property['name']] = property['value']['value']
        else
          #     releasePromises.push(helper.releaseObject(@element._client, property.value))
        end
        # releasePromises = [helper.releaseObject(@element._client, remote_object)]
      end
    end

    ####################
    # JS snippets
    ####################

    GET_PATH_JS = <<~JS
      function() {
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

    CURRENT_NODE_SELECTED_JS = <<~JS
      function() {
        let selectedNode = document.getSelection().focusNode;
        if (!selectedNode)
          return false;
        if (selectedNode.nodeType == 3)
          selectedNode = selectedNode.parentNode;
        return this.contains(selectedNode);
      }
    JS

    FIND_CSS_JS = <<~JS
      function(selector){
        return Array.from(this.querySelectorAll(selector));
      }
    JS

    FIND_XPATH_JS = <<~JS
      function(selector){
        const xpath = document.evaluate(selector, this, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
        let results = [];
        for (let i=0; i < xpath.snapshotLength; i++){
          results.push(xpath.snapshotItem(i));
        }
        return results;
      }
    JS

    ELEMENT_VISIBLE_TEXT_JS = <<~JS
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

    GET_ATTRIBUTES_JS = <<~JS
      function(){
        let attrs = {};
        for (let attr of this.attributes)
          attrs[attr.name] = attr.value.replace("\\n","\\\\n");
        return attrs;
      }
    JS

    GET_VALUE_JS = <<~JS
      function(){
        if ((this.tagName == 'SELECT') && this.multiple){
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

    SELECT_OPTION_JS = <<~JS
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

    UNSELECT_OPTION_JS = <<~JS
      function(){
        let sel = this.parentNode;
        if (sel.tagName == 'OPTGROUP') {
          sel = sel.parentNode;
        }

        if (!sel.multiple){
          return false;
        }

        this.selected = false;
        return true;
      }
    JS

    # if an area element, check visibility of relevant image
    VISIBLE_JS = <<~JS
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

    DELETE_TEXT_JS = <<~JS
      function(){
        range = document.createRange();
        range.selectNodeContents(this);
        window.getSelection().removeAllRanges();
        window.getSelection().addRange(range);
        window.getSelection().deleteFromDocument();
        window.getSelection().removeAllRanges();
      }
    JS

    GET_BOUNDING_CLIENT_RECT_JS = <<~JS
      function(){
        rect = this.getBoundingClientRect();
        return rect.toJSON();
      }
    JS

    ELEMENT_DISABLED_JS = <<~JS
      function() {
        const xpath = 'parent::optgroup[@disabled] | \
                       ancestor::select[@disabled] | \
                       parent::fieldset[@disabled] | \
                       ancestor::*[not(self::legend) or preceding-sibling::legend][parent::fieldset[@disabled]]';
        return this.disabled || document.evaluate(xpath, this, null, XPathResult.BOOLEAN_TYPE, null).booleanValue
      }
    JS

    ELEMENT_PROP_OR_ATTR_JS = <<~JS
      function(name){
        if (((this.tagName == 'img') && (name == 'src')) ||
            ((this.tagName == 'a') && (name == 'href')))
          return this.getAttribute(name) && this[name];

        let value = this[name];
        if ((value == null) || (typeof value == 'object'))
          value = this.getAttribute(name);
        return value
      }
    JS
  end
end
