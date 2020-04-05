# frozen_string_literal: true

module Capybara::Apparition
  module Drag
    def drag_to(other, delay: 0.1, html5: nil, drop_modifiers: [])
      drop_modifiers = Array(drop_modifiers)

      driver.execute_script MOUSEDOWN_TRACKER
      scroll_if_needed
      m = @page.mouse
      m.move_to(**visible_center)
      sleep delay
      m.down
      html5 = !driver.evaluate_script(LEGACY_DRAG_CHECK, self) if html5.nil?
      if html5
        driver.execute_script HTML5_DRAG_DROP_SCRIPT, self, other, delay, drop_modifiers
        m.up(**other.visible_center)
      else
        @page.keyboard.with_keys(drop_modifiers) do
          other.scroll_if_needed
          sleep delay
          m.move_to(**other.visible_center)
          sleep delay
        ensure
          m.up
          sleep delay
        end
      end
    end

    def drag_by(x, y, delay: 0.1)
      pos = visible_center
      raise ::Capybara::Apparition::MouseEventImpossible.new(self, 'args' => ['hover']) if pos.nil?

      other_pos = { x: pos[:x] + x, y: pos[:y] + y }
      raise ::Capybara::Apparition::MouseEventFailed.new(self, 'args' => ['drag', test['selector'], pos]) unless mouse_event_test?(**pos)

      @page.mouse.move_to(**pos).down
      sleep delay
      @page.mouse.move_to(**other_pos)
      sleep delay
      @page.mouse.up
    end

    def drop(*args)
      if args[0].is_a? String
        input = evaluate_on ATTACH_FILE
        tag_name = input['description'].split(/[\.#]/, 2)[0]
        input = Capybara::Apparition::Node.new(driver, @page, input['objectId'], tag_name: tag_name)
        input.set(args)
        evaluate_on DROP_FILE, objectId: input.id
      else
        items = args.each_with_object([]) do |arg, arr|
          arg.each_with_object(arr) do |(type, data), arr_|
            arr_ << { type: type, data: data }
          end
        end
        evaluate_on DROP_STRING, value: items
      end
    end

    DROP_STRING = <<~JS
      function(strings){
        var dt = new DataTransfer(),
            opts = { cancelable: true, bubbles: true, dataTransfer: dt };
        for (var i=0; i < strings.length; i++){
          if (dt.items) {
            dt.items.add(strings[i]['data'], strings[i]['type']);
          } else {
            dt.setData(strings[i]['type'], strings[i]['data']);
          }
        }
        var dropEvent = new DragEvent('drop', opts);
        this.dispatchEvent(dropEvent);
      }
    JS

    DROP_FILE = <<~JS
      function(input){
        var files = input.files,
            dt = new DataTransfer(),
            opts = { cancelable: true, bubbles: true, dataTransfer: dt };
        input.parentElement.removeChild(input);
        if (dt.items){
          for (var i=0; i<files.length; i++){
            dt.items.add(files[i]);
          }
        } else {
          Object.defineProperty(dt, "files", {
            value: files,
            writable: false
          });
        }
        var dropEvent = new DragEvent('drop', opts);
        this.dispatchEvent(dropEvent);
      }
    JS

    ATTACH_FILE = <<~JS
      function(){
        var input = document.createElement('INPUT');
        input.type = "file";
        input.id = "_capybara_drop_file";
        input.multiple = true;
        document.body.appendChild(input);
        return input;
      }
    JS

    MOUSEDOWN_TRACKER = <<~JS
      window.capybara_mousedown_prevented = null;
      document.addEventListener('mousedown', ev => {
        window.capybara_mousedown_prevented = ev.defaultPrevented;
      }, { once: true, passive: true })
    JS

    LEGACY_DRAG_CHECK = <<~JS
      (function(el){
        if ([true, null].includes(window.capybara_mousedown_prevented)){
          return true;
        }
        do {
          if (el.draggable) return false;
        } while (el = el.parentElement );
        return true;
      })(arguments[0])
    JS

    HTML5_DRAG_DROP_SCRIPT = <<~JS
      let source = arguments[0];
      const target = arguments[1];
      const step_delay = arguments[2] * 1000;
      const drop_modifiers = arguments[3];
      const key_aliases = {
        'cmd': 'meta',
        'command': 'meta',
        'control': 'ctrl',
      };

      function rectCenter(rect){
        return new DOMPoint(
          (rect.left + rect.right)/2,
          (rect.top + rect.bottom)/2
        );
      }

      function pointOnRect(pt, rect) {
      	var rectPt = rectCenter(rect);
      	var slope = (rectPt.y - pt.y) / (rectPt.x - pt.x);

      	if (pt.x <= rectPt.x) { // left side
      		var minXy = slope * (rect.left - pt.x) + pt.y;
      		if (rect.top <= minXy && minXy <= rect.bottom)
            return new DOMPoint(rect.left, minXy);
      	}

      	if (pt.x >= rectPt.x) { // right side
      		var maxXy = slope * (rect.right - pt.x) + pt.y;
      		if (rect.top <= maxXy && maxXy <= rect.bottom)
            return new DOMPoint(rect.right, maxXy);
      	}

      	if (pt.y <= rectPt.y) { // top side
      		var minYx = (rectPt.top - pt.y) / slope + pt.x;
      		if (rect.left <= minYx && minYx <= rect.right)
            return new DOMPoint(minYx, rect.top);
      	}

      	if (pt.y >= rectPt.y) { // bottom side
      		var maxYx = (rect.bottom - pt.y) / slope + pt.x;
      		if (rect.left <= maxYx && maxYx <= rect.right)
            return new DOMPoint(maxYx, rect.bottom);
      	}

        return new DOMPoint(pt.x,pt.y);
      }

      function dragStart() {
        return new Promise( resolve => {
          var dragEvent = new DragEvent('dragstart', opts);
          source.dispatchEvent(dragEvent);
          setTimeout(resolve, step_delay)
        })
      }

      function dragEnter() {
        return new Promise( resolve => {
          target.scrollIntoView({behavior: 'instant', block: 'center', inline: 'center'});
          let targetRect = target.getBoundingClientRect(),
          sourceCenter = rectCenter(source.getBoundingClientRect());

          drop_modifiers.map(key => key_aliases[key] || key)
                        .forEach(key => opts[key + 'Key'] = true);

          // fire 2 dragover events to simulate dragging with a direction
          let entryPoint = pointOnRect(sourceCenter, targetRect);
          let dragOverOpts = Object.assign({clientX: entryPoint.x, clientY: entryPoint.y}, opts);
          let dragOverEvent = new DragEvent('dragover', dragOverOpts);
          target.dispatchEvent(dragOverEvent);
          setTimeout(resolve, step_delay)
        })
      }

      function dragOnto() {
        return new Promise( resolve => {
          var targetCenter = rectCenter(target.getBoundingClientRect());
          dragOverOpts = Object.assign({clientX: targetCenter.x, clientY: targetCenter.y}, opts);
          dragOverEvent = new DragEvent('dragover', dragOverOpts);
          target.dispatchEvent(dragOverEvent);
          setTimeout(resolve, step_delay, { drop: dragOverEvent.defaultPrevented, opts: dragOverOpts});
        })
      }

      function dragLeave({ drop, opts: dragOverOpts }) {
        return new Promise( resolve => {
          var dragLeaveOptions = { ...opts, ...dragOverOpts };
          var dragLeaveEvent = new DragEvent('dragleave', dragLeaveOptions);
          target.dispatchEvent(dragLeaveEvent);
          if (drop) {
            var dropEvent = new DragEvent('drop', dragLeaveOptions);
            target.dispatchEvent(dropEvent);
          }
          var dragEndEvent = new DragEvent('dragend', dragLeaveOptions);
          source.dispatchEvent(dragEndEvent);
          setTimeout(resolve, step_delay);
        })
      }

      const dt = new DataTransfer();
      const opts = { cancelable: true, bubbles: true, dataTransfer: dt };

      while (source && !source.draggable) {
        source = source.parentElement;
      }

      if (source.tagName == 'A'){
        dt.setData('text/uri-list', source.href);
        dt.setData('text', source.href);
      }
      if (source.tagName == 'IMG'){
        dt.setData('text/uri-list', source.src);
        dt.setData('text', source.src);
      }

      dragStart().then(dragEnter).then(dragOnto).then(dragLeave)
    JS
  end
end
