# frozen_string_literal: true

require 'spec_helper'

skip = []
Capybara::SpecHelper.run_specs TestSessions::Apparition, 'Apparition', capybara_skip: skip

describe Capybara::Session do
  context 'with apparition driver' do
    before do
      @session = TestSessions::Apparition
    end

    after do
      @session.reset!
    end

    describe Capybara::Apparition::Node do
      it 'raises an error if the element has been removed from the DOM' do
        @session.visit('/apparition/with_js')
        node = @session.find(:css, '#remove_me')
        expect(node.text).to eq('Remove me')
        @session.find(:css, '#remove').click
        expect { node.text }.to raise_error(Capybara::Apparition::ObsoleteNode)
      end

      it 'raises an error if the element was on a previous page' do
        @session.visit('/apparition/index')
        node = @session.find('.//a')
        @session.execute_script "window.location = 'about:blank'"
        sleep 0.1 # allow the window time to load new location
        expect { node.text }.to raise_error(Capybara::Apparition::ObsoleteNode)
      end

      it 'raises an error if the element is not visible' do
        @session.visit('/apparition/index')
        @session.execute_script "document.querySelector('a[href=js_redirect]').style.display = 'none'"
        expect { @session.click_link 'JS redirect' }.to raise_error(Capybara::ElementNotFound)
      end

      it 'hovers an element' do
        @session.visit('/apparition/with_js')
        expect(@session.find(:css, '#hidden_link span', visible: false)).not_to be_visible
        @session.find(:css, '#hidden_link').hover
        expect(@session.find(:css, '#hidden_link span')).to be_visible
      end

      it 'hovers an element before clicking it' do
        @session.visit('/apparition/with_js')
        @session.click_link 'Hidden link'
        expect(@session.current_path).to eq('/')
      end

      it 'does not raise error when asserting svg elements with a count that is not what is in the dom' do
        @session.visit('/apparition/with_js')
        expect { @session.has_css?('svg circle', count: 2) }.not_to raise_error
        expect(@session).not_to have_css('svg circle', count: 2)
      end

      context 'when someone (*cough* prototype *cough*) messes with Array#toJSON' do
        before do
          @session.visit('/apparition/index')
          array_munge = <<~JS
            Array.prototype.toJSON = function() {
              return "ohai";
            }
          JS
          @session.execute_script array_munge
        end

        it 'gives a proper error' do
          expect { @session.find(:css, 'username') }.to raise_error(Capybara::ElementNotFound)
        end
      end

      context 'when someone messes with JSON' do
        # mootools <= 1.2.4 replaced the native JSON with it's own JSON that didn't have stringify or parse methods
        it 'works correctly' do
          @session.visit('/apparition/index')
          @session.execute_script('JSON = {};')
          expect { @session.find(:link, 'JS redirect') }.not_to raise_error
        end
      end

      context 'when the element is not in the viewport' do
        before do
          @session.visit('/apparition/with_js')
        end

        it 'raises a MouseEventFailed error' do
          expect { @session.click_link('O hai') }.to raise_error(Capybara::Apparition::MouseEventFailed)
        end

        context 'and is then brought in' do
          before do
            @session.execute_script "$('#off-the-left').animate({left: '10'});"
            Capybara.default_max_wait_time = 1
          end

          after do
            Capybara.default_max_wait_time = 0
          end

          it 'clicks properly' do
            expect { @session.click_link 'O hai' }.not_to raise_error
          end
        end
      end
    end

    context 'when the element is not in the viewport of parent element' do
      before do
        @session.visit('/apparition/scroll')
      end

      it 'scrolls into view' do
        @session.click_link 'Link outside viewport'
        sleep 1
        expect(@session.current_path).to eq('/')
      end

      it 'scrolls into view if scrollIntoViewIfNeeded fails' do
        @session.click_link 'Below the fold'
        sleep 1
        expect(@session.current_path).to eq('/')
      end
    end

    describe 'Node#select' do
      before do
        @session.visit('/apparition/with_js')
      end

      context 'when selected option is not in optgroup' do
        before do
          @session.find(:select, 'browser').find(:option, 'Firefox').select_option
        end

        it 'fires the focus event' do
          expect(@session.find(:css, '#changes_on_focus').text).to eq('Apparition')
        end

        it 'fire the change event' do
          expect(@session.find(:css, '#changes').text).to eq('Firefox')
        end

        it 'fires the blur event' do
          expect(@session.find(:css, '#changes_on_blur').text).to eq('Firefox')
        end

        it 'fires the change event with the correct target' do
          expect(@session.find(:css, '#target_on_select').text).to eq('SELECT')
        end
      end

      context 'when selected option is in optgroup' do
        before do
          @session.find(:select, 'browser').find(:option, 'Safari').select_option
        end

        it 'fires the focus event' do
          expect(@session.find(:css, '#changes_on_focus').text).to eq('Apparition')
        end

        it 'fire the change event' do
          expect(@session.find(:css, '#changes').text).to eq('Safari')
        end

        it 'fires the blur event' do
          expect(@session.find(:css, '#changes_on_blur').text).to eq('Safari')
        end

        it 'fires the change event with the correct target' do
          expect(@session.find(:css, '#target_on_select').text).to eq('SELECT')
        end
      end
    end

    describe 'Node#set' do
      before do
        @session.visit('/apparition/with_js')
        @session.find(:css, '#change_me').set('Hello!')
      end

      it 'fires the change event' do
        # click outside the field to trigger the change event
        @session.find(:css, 'body').click
        expect(@session.find(:css, '#changes').text).to eq('Hello!')
      end

      it 'fires the input events' do
        expect(@session.find(:css, '#changes_on_input').text).to eq('Hello!')
      end

      it 'accepts numbers in a maxlength field' do
        element = @session.find(:css, '#change_me_maxlength')
        element.set 100
        expect(element.value).to eq('100')
      end

      it 'accepts negatives in a number field' do
        element = @session.find(:css, '#change_me_number')
        element.set(-100)
        expect(element.value).to eq('-100')
      end

      it 'fires the keydown event' do
        expect(@session.find(:css, '#changes_on_keydown').text).to eq('6')
      end

      it 'fires the keyup event' do
        expect(@session.find(:css, '#changes_on_keyup').text).to eq('6')
      end

      it 'fires the keypress event' do
        expect(@session.find(:css, '#changes_on_keypress').text).to eq('6')
      end

      it 'fires the focus event' do
        expect(@session.find(:css, '#changes_on_focus').text).to eq('Focus')
      end

      it 'fires the blur event' do
        # click outside the field to trigger the blur event
        @session.find(:css, 'body').click
        expect(@session.find(:css, '#changes_on_blur').text).to eq('Blur')
      end

      it 'fires the keydown event before the value is updated' do
        expect(@session.find(:css, '#value_on_keydown').text).to eq('Hello')
      end

      it 'fires the keyup event after the value is updated' do
        expect(@session.find(:css, '#value_on_keyup').text).to eq('Hello!')
      end

      it 'clears the input before setting the new value' do
        element = @session.find(:css, '#change_me')
        element.set ''
        expect(element.value).to eq('')
      end

      it 'supports special characters' do
        element = @session.find(:css, '#change_me')
        element.set '$52.00'
        expect(element.value).to eq('$52.00')
      end

      it 'attaches a file when passed a Pathname' do
        file = Tempfile.create('a_test_pathname') do |f|
          f.write('text')
          f
        end
        element = @session.find(:css, '#change_me_file').set(file.path)
        expect(element.value).to match(/^C:\\fakepath\\a_test_pathname/)
      end

      it'handles foreign characters' do
        element = @session.find(:css, '#change_me')
        element.set 'Retourestraße'
        expect(element.value).to eq('Retourestraße')
      end
    end

    describe 'Node#visible' do
      before do
        @session.visit('/apparition/visible')
      end

      it 'considers display: none to not be visible' do
        expect(@session.find(:css, 'li', text: 'Display None', visible: false).visible?).to be false
      end

      it 'considers visibility: hidden to not be visible' do
        expect(@session.find(:css, 'li', text: 'Hidden', visible: false).visible?).to be false
      end

      it 'considers opacity: 0 to not be visible' do
        expect(@session.find(:css, 'li', text: 'Transparent', visible: false).visible?).to be false
      end

      it 'element with all children hidden returns empty text' do
        expect(@session.find(:css, 'div').text).to eq('')
      end
    end

    describe 'Node#checked?' do
      before do
        @session.visit '/apparition/attributes_properties'
      end

      it 'is a boolean' do
        expect(@session.find_field('checked').checked?).to be true
        expect(@session.find_field('unchecked').checked?).to be false
      end
    end

    describe 'Node#[]' do
      before do
        @session.visit '/apparition/attributes_properties'
      end

      it 'gets normalized href' do
        expect(@session.find(:link, 'Loop')['href']).to eq("http://#{@session.server.host}:#{@session.server.port}/apparition/attributes_properties")
      end

      it 'gets innerHTML' do
        expect(@session.find(:css, '.some_other_class')['innerHTML']).to eq '<p>foobar</p>'
      end

      it 'gets attribute' do
        link = @session.find(:link, 'Loop')
        expect(link['data-random']).to eq '42'
        expect(link['onclick']).to eq 'return false;'
      end

      it 'gets boolean attributes as booleans' do
        expect(@session.find_field('checked')['checked']).to be true
        expect(@session.find_field('unchecked')['checked']).to be false
      end
    end

    describe 'Node#==' do
      it "doesn't equal a node from another page" do
        @session.visit('/apparition/simple')
        @elem1 = @session.find(:css, '#nav')
        @session.visit('/apparition/set')
        @elem2 = @session.find(:css, '#filled_div')
        expect(@elem2 == @elem1).to be false
        expect(@elem1 == @elem2).to be false
      end

      it 'equals if the same node' do
        @session.visit('/apparition/set')
        @elem1 = @session.find(:css, '#filled_div')
        @elem2 = @session.find(:css, '#filled_div')
        expect(@elem1 == @elem2).to be true
      end
    end

    it 'has no trouble clicking elements when the size of a document changes' do
      @session.visit('/apparition/long_page')
      @session.find(:css, '#penultimate').click
      @session.execute_script <<~JS
        el = document.getElementById('penultimate')
        el.parentNode.removeChild(el)
      JS
      @session.click_link('Phasellus blandit velit')
      expect(@session).to have_content('Hello')
    end

    it 'handles clicks where the target is in view, but the document is smaller than the viewport' do
      @session.visit '/apparition/simple'
      @session.click_link 'Link'
      expect(@session).to have_content('Hello world')
    end

    it 'handles clicks where a parent element has a border' do
      @session.visit '/apparition/table'
      @session.click_link 'Link'
      expect(@session).to have_content('Hello world')
    end

    it 'handles window.confirm(), returning true unconditionally' do
      @session.visit '/'
      expect(@session.evaluate_script("window.confirm('foo')")).to be true
    end

    it 'handles window.prompt(), returning the default value or null' do
      @session.visit '/'
      expect(@session.evaluate_script("window.prompt('foo', 'default')")).to eq('default')
    end

    it 'handles evaluate_script values properly' do
      @session.visit '/'
      expect(@session.evaluate_script('null')).to be_nil
      expect(@session.evaluate_script('false')).to be false
      expect(@session.evaluate_script('true')).to be true
      expect(@session.evaluate_script("{foo: 'bar'}")).to eq('foo' => 'bar')
    end

    it 'can evaluate a statement ending with a semicolon' do
      expect(@session.evaluate_script('3;')).to eq(3)
    end

    it 'returns element when no elements passed in' do
      @session.visit('/with_js')
      change = @session.find(:css, '#change')
      el = @session.evaluate_script("document.getElementById('change')")
      expect(el).to be_instance_of(Capybara::Node::Element)
      expect(el).to eq(change)
    end

    it 'returns element when element passed in' do
      @session.visit('/with_js')
      change = @session.find(:css, '#change')
      el = @session.evaluate_script('arguments[0]', change)
      expect(el).to be_instance_of(Capybara::Node::Element)
      expect(el).to eq(change)
    end

    it 'synchronises page loads properly' do
      @session.visit '/apparition/index'
      @session.click_link 'JS redirect'
      expect(@session.html).to include('Hello world')
    end

    context 'click tests' do
      before do
        @session.visit '/apparition/click_test'
        @orig_size = @session.current_window.size
      end

      after do
        @session.current_window.resize_to(*@orig_size)
      end

      it 'scrolls around so that elements can be clicked' do
        @session.current_window.resize_to(200, 200)
        log = @session.find(:css, '#log')

        instructions = %w[one four one two three]
        instructions.each do |instruction, _i|
          @session.find(:css, "##{instruction}").click
          expect(log.text).to eq(instruction)
        end
      end

      # See https://github.com/teamapparition/apparition/issues/60
      it 'fixes some weird layout issue that we are not entirely sure about the reason for' do
        @session.visit '/apparition/datepicker'
        @session.find(:css, '#datepicker').set('2012-05-11')
        @session.click_link 'some link'
      end

      it 'can click an element inside an svg' do
        expect do
          @session.find(:css, '#myrect').click
        end.not_to raise_error
      end

      context 'with #two overlapping #one' do
        before do
          @session.execute_script <<~JS
            var two = document.getElementById('two')
            two.style.position = 'absolute'
            two.style.left     = '0px'
            two.style.top      = '0px'
          JS
          @session.execute_script('window.scrollTo(0,0)')
        end

        it 'detects if an element is obscured when clicking' do
          expect do
            @session.find(:css, '#one').click
          end.to raise_error(Capybara::Apparition::MouseEventFailed) { |error|
            # expect(error.selector).to eq('html body div#two.box')
            expect(error.selector).to match(/div#two/)
            expect(error.message).to match(/at co-ordinates \[\d+, \d+\]/)
          }
        end

        it 'clicks in the centre of an element' do
          expect do
            @session.find(:css, '#one').click
          end.to raise_error(Capybara::Apparition::MouseEventFailed) { |error|
            expect(error.position).to eq([200, 200])
          }
        end

        it 'clicks in the centre of an element within the viewport, if part is outside the viewport' do
          @session.current_window.resize_to(200, 200)

          expect do
            @session.find(:css, '#one').click
          end.to raise_error(Capybara::Apparition::MouseEventFailed) { |error|
            expect(error.position.first).to eq(150)
          }
        end
      end

      context 'with #svg overlapping #one' do
        before do
          @session.execute_script <<~JS
            var two = document.getElementById('svg')
            two.style.position = 'absolute'
            two.style.left     = '0px'
            two.style.top      = '0px'
          JS
          @session.execute_script('window.scrollTo(0,0)')
        end

        it 'detects if an element is obscured when clicking' do
          expect do
            @session.find(:css, '#one').click
          end.to raise_error(Capybara::Apparition::MouseEventFailed) { |error|
            # TODO: improve the error selector - but it could be from a parent frame
            expect(error.selector).to match(/svg#svg/)
            expect(error.message).to include('[200, 200]')
          }
        end
      end

      context 'with image maps' do
        before do
          @session.visit('/apparition/image_map')
        end

        it 'can click' do
          @session.find(:css, 'map[name=testmap] area[shape=circle]').click
          expect(@session).to have_css('#log', text: 'circle clicked')
          @session.find(:css, 'map[name=testmap] area[shape=rect]').click
          expect(@session).to have_css('#log', text: 'rect clicked')
        end

        it "doesn't click if the associated img is hidden" do
          expect do
            @session.find(:css, 'map[name=testmap2] area[shape=circle]').click
          end.to raise_error(Capybara::ElementNotFound)
          expect do
            @session.find(:css, 'map[name=testmap2] area[shape=circle]', visible: false).click
          end.to raise_error(Capybara::Apparition::MouseEventFailed)
        end
      end
    end

    context 'double click tests' do
      before do
        @session.visit '/apparition/double_click_test'
        @orig_size = @session.current_window.size
      end

      after { @session.current_window.resize_to(*@orig_size) }

      it 'double clicks properly' do
        @session.current_window.resize_to(200, 200)
        log = @session.find(:css, '#log')

        instructions = %w[one four one two three]
        instructions.each do |instruction, _i|
          @session.find(:css, "##{instruction}").base.double_click
          expect(log.text).to eq(instruction)
        end
      end
    end

    context 'status code support', :status_code_support do
      it 'determines status code when an user goes to a page by using a link on it' do
        @session.visit '/apparition/with_different_resources'

        @session.click_link 'Go to 500'
        expect(@session.status_code).to eq(500)
      end

      it 'determines properly status code when an user goes through a few pages' do
        @session.visit '/apparition/with_different_resources'
        sleep 0.1
        @session.click_link 'Go to 201'
        sleep 0.1
        @session.click_link 'Do redirect'
        sleep 0.1
        @session.click_link 'Go to 402'
        sleep 0.1
        expect(@session.status_code).to eq(402)
      end
    end

    it 'ignores cyclic structure errors in evaluate_script' do
      code = <<~JS
        (function() {
          var a = {};
          var b = {};
          var c = {};
          c.a = a;
          a.a = a;
          a.b = b;
          a.c = c;
          return a;
        })()
      JS
      expect(@session.evaluate_script(code)).to eq('a' => '(cyclic structure)', 'b' => {}, 'c' => { 'a' => '(cyclic structure)' })
    end

    it 'returns BR as \\n in #text' do
      @session.visit '/apparition/simple'
      expect(@session.find(:css, '#break').text).to eq("Foo\nBar")
    end

    it 'handles hash changes' do
      @session.visit '/#omg'
      expect(@session.current_url).to match(%r{/#omg$})
      @session.execute_script <<~JS
        window.onhashchange = function() { window.last_hashchange = window.location.hash }
      JS
      @session.visit '/#foo'
      expect(@session.current_url).to match(%r{/#foo$})
      expect(@session.evaluate_script('window.last_hashchange')).to eq('#foo')
    end

    context 'current_url' do
      let(:request_uri) { URI.parse(@session.current_url).request_uri }

      it 'supports whitespace characters' do
        @session.visit '/apparition/arbitrary_path/200/foo%20bar%20baz'
        expect(@session.current_path).to eq('/apparition/arbitrary_path/200/foo%20bar%20baz')
      end

      it 'supports escaped characters' do
        @session.visit '/apparition/arbitrary_path/200/foo?a%5Bb%5D=c'
        expect(request_uri).to eq('/apparition/arbitrary_path/200/foo?a%5Bb%5D=c')
      end

      it 'supports url in parameter' do
        @session.visit '/apparition/arbitrary_path/200/foo%20asd?a=http://example.com/asd%20asd'
        expect(request_uri).to eq('/apparition/arbitrary_path/200/foo%20asd?a=http://example.com/asd%20asd')
      end

      it 'supports restricted characters " []:/+&="' do
        @session.visit '/apparition/arbitrary_path/200/foo?a=%20%5B%5D%3A%2F%2B%26%3D'
        expect(request_uri).to eq('/apparition/arbitrary_path/200/foo?a=%20%5B%5D%3A%2F%2B%26%3D')
      end
    end

    context 'basic dragging support' do
      before do
        @session.visit '/apparition/drag'
      end

      it 'supports drag_to' do
        draggable = @session.find(:css, '#drag_to #draggable')
        droppable = @session.find(:css, '#drag_to #droppable')

        draggable.drag_to(droppable)
        expect(droppable).to have_content('Dropped')
      end

      it 'supports drag_by on native element' do
        draggable = @session.find(:css, '#drag_by .draggable')

        top_before = @session.evaluate_script('$("#drag_by .draggable").position().top')
        left_before = @session.evaluate_script('$("#drag_by .draggable").position().left')

        draggable.native.drag_by(15, 15)

        top_after = @session.evaluate_script('$("#drag_by .draggable").position().top')
        left_after = @session.evaluate_script('$("#drag_by .draggable").position().left')

        expect(top_after).to eq(top_before + 15)
        expect(left_after).to eq(left_before + 15)
      end
    end

    context 'HTML5 dragging support' do
      before do
        @session.visit '/with_js'
      end

      it 'should HTML5 drag and drop an object' do
        element = @session.find('//div[@id="drag_html5"]')
        target = @session.find('//div[@id="drop_html5"]')
        element.drag_to(target)
        expect(@session).to have_xpath('//div[contains(., "HTML5 Dropped drag_html5")]')
      end

      it 'should set clientX/Y in dragover events' do
        skip 'Not valid until Capybara 3.13' if Gem.loaded_specs['capybara'].version < Gem::Version.new('3.13.0')
        element = @session.find('//div[@id="drag_html5"]')
        target = @session.find('//div[@id="drop_html5"]')
        element.drag_to(target)
        expect(@session).to have_css('div.log', text: /DragOver with client position: [1-9]\d*,[1-9]\d*/, count: 2)
      end

      it 'should not HTML5 drag and drop on a non HTML5 drop element' do
        element = @session.find('//div[@id="drag_html5"]')
        target = @session.find('//div[@id="drop_html5"]')
        target.execute_script("$(this).removeClass('drop');")
        element.drag_to(target)
        sleep 1
        expect(@session).not_to have_xpath('//div[contains(., "HTML5 Dropped drag_html5")]')
      end

      it 'should HTML5 drag and drop when scrolling needed' do
        element = @session.find('//div[@id="drag_html5_scroll"]')
        target = @session.find('//div[@id="drop_html5_scroll"]')
        element.drag_to(target)
        expect(@session).to have_xpath('//div[contains(., "HTML5 Dropped drag_html5_scroll")]')
      end

      it 'should drag HTML5 default draggable elements' do
        link = @session.find_link('drag_link_html5')
        target = @session.find(:id, 'drop_html5')
        link.drag_to target
        expect(@session).to have_xpath('//div[contains(., "HTML5 Dropped")]')
      end
    end

    context 'Window support' do
      describe '#size' do
        # We base size on innerWidth and innerHeight since each "tab" can have its own size
        # This replaces some Capybara tests which fail to the use of outerWidth and outerHeight

        def win_size
          @session.evaluate_script('[window.innerWidth, window.innerHeight]')
        end

        it 'should return size of whole window', requires: %i[windows js] do
          expect(@session.current_window.size).to eq win_size
        end

        it 'should switch to original window if invoked not for current window' do
          @window = @session.current_window
          @session.visit('/with_windows')

          @other_window = @session.window_opened_by do
            @session.find(:css, '#openWindow').click
            sleep 2
          end

          sleep 1

          size = @session.within_window(@other_window) do
            win_size
          end

          expect(@other_window.size).to eq(size)
          expect(@session.current_window).to eq(@window)
          @other_window.close
        end
      end
    end

    context 'window switching support', requires: [:windows] do
      before do
        @window = @session.current_window
      end

      after do
        (@session.windows - [@window]).each(&:close)
      end

      it 'waits for a new window to load' do
        @session.visit '/'

        popup = @session.window_opened_by(wait: 3) do
          @session.execute_script <<~JS
            window.open('/apparition/slow', 'popup')
          JS
        end

        @session.within_window(popup) do
          expect(@session.html).to include('slow page')
          @session.execute_script('window.close()')
        end
      end

      it 'can access a second window of the same name' do
        @session.visit '/'

        popup = @session.window_opened_by(wait: 5) do
          @session.execute_script <<~JS
            window.open('/apparition/simple', 'popup')
          JS
        end

        sleep 1

        @session.within_window(popup) do
          expect(@session.html).to include('Test')
          @session.execute_script('window.close()')
        end

        another_popup = @session.window_opened_by(wait: 5) do
          @session.execute_script <<~JS
            window.open('/apparition/simple', 'popup')
          JS
        end

        sleep 1

        @session.within_window(another_popup) do
          expect(@session.html).to include('Test')
        end
      end
    end

    context 'frame support', requires: [:frames] do
      it 'supports selection by index' do
        @session.visit '/apparition/frames'
        @session.within_frame 0 do
          sleep 1
          expect(@session.driver.frame_url).to match %r{/apparition/slow$}
        end
      end

      it 'supports selection by element' do
        @session.visit '/apparition/frames'
        frame = @session.find(:css, 'iframe[name]')

        @session.within_frame(frame) do
          sleep 1
          expect(@session.driver.frame_url).to match %r{/apparition/slow$}
        end
      end

      it 'supports selection by element without name or id' do
        @session.visit '/apparition/frames'
        frame = @session.find(:css, 'iframe:not([name]):not([id])')

        @session.within_frame(frame) do
          sleep 1
          expect(@session.driver.frame_url).to match %r{/apparition/headers$}
        end
      end

      it 'supports selection by element with id but no name' do
        @session.visit '/apparition/frames'
        frame = @session.find(:css, 'iframe[id]:not([name])')

        @session.within_frame(frame) do
          sleep 1
          expect(@session.driver.frame_url).to match %r{/apparition/get_cookie$}
        end
      end

      it 'waits for the frame to load' do
        @session.visit '/'

        @session.execute_script <<~JS
          document.body.innerHTML += '<iframe src="/apparition/slow" name="frame">'
        JS

        @session.within_frame 'frame' do
          expect(@session.driver.frame_url).to match %r{/apparition/slow$}
          expect(@session.html).to include('slow page')
        end

        expect(@session.current_path).to eq('/')
      end

      it 'waits for the cross-domain frame to load' do
        @session.visit '/apparition/frames'
        expect(@session.current_path).to eq('/apparition/frames')

        @session.within_frame 'frame' do
          expect(@session.driver.frame_url).to match %r{/apparition/slow$}
          expect(@session.body).to include('slow page')
        end

        expect(@session.current_path).to eq('/apparition/frames')
      end

      context 'with src == about:blank' do
        it "doesn't hang if no document created" do
          @session.visit '/'
          @session.execute_script <<~JS
            document.body.insertAdjacentHTML("beforeend", '<iframe src="about:blank" name="frame">')
          JS
          @session.within_frame 'frame' do
            expect(@session).to have_no_xpath('/html/body/*')
          end
        end

        it "doesn't hang if built by JS" do
          @session.visit '/'
          @session.execute_script <<~JS
            document.body.insertAdjacentHTML("beforeend", '<iframe src="about:blank" name="frame">');
            var iframeDocument = document.querySelector('iframe[name="frame"]').contentWindow.document;
            var content = '<html><body><p>Hello Frame</p></body></html>';
            iframeDocument.open('text/html', 'replace');
            iframeDocument.write(content);
            iframeDocument.close();
          JS

          @session.within_frame 'frame' do
            expect(@session).to have_content('Hello Frame')
          end
        end
      end

      context 'with no src attribute' do
        it "doesn't hang if the srcdoc attribute is used" do
          @session.visit '/'
          @session.execute_script <<~JS
            document.body.insertAdjacentHTML("beforeend", '<iframe srcdoc="<p>Hello Frame</p>" name="frame">')
          JS

          @session.within_frame 'frame' do
            expect(@session).to have_content('Hello Frame', wait: false)
          end
        end

        it "doesn't hang if the frame is filled by JS" do
          @session.visit '/'

          @session.execute_script <<~JS
            document.body.insertAdjacentHTML("beforeend", '<iframe id="frame" name="frame">')
          JS

          @session.execute_script <<~JS
            var iframeDocument = document.querySelector('#frame').contentWindow.document;
            var content = '<html><body><p>Hello Frame</p></body></html>';
            iframeDocument.open('text/html', 'replace');
            iframeDocument.write(content);
            iframeDocument.close();
          JS

          @session.within_frame 'frame' do
            expect(@session).to have_content('Hello Frame', wait: false)
          end
        end
      end

      it 'supports clicking in a frame' do
        @session.visit '/'

        @session.execute_script <<~JS
          document.body.insertAdjacentHTML("beforeend", '<iframe src="/apparition/click_test" name="frame">')
        JS

        @session.within_frame 'frame' do
          log = @session.find(:css, '#log', wait: 2)
          one = @session.find(:css, '#one')
          one.click
          sleep 5
          expect(log.text).to eq('one')
        end
      end

      it 'supports clicking in a frame with padding' do
        @session.visit '/'

        @session.execute_script <<~JS
          document.body.insertAdjacentHTML("beforeend", '<iframe src="/apparition/click_test" name="padded_frame" style="padding:100px;">')
        JS

        @session.within_frame 'padded_frame' do
          log = @session.find(:css, '#log')
          @session.find(:css, '#one').click
          expect(log.text).to eq('one')
        end
      end

      it 'supports clicking in a frame nested in a frame' do
        @session.visit '/'

        # The padding on the frame here is to differ the sizes of the two
        # frames, ensuring that their offsets are being calculated seperately.
        # This avoids a false positive where the same frame's offset is
        # calculated twice, but the click still works because both frames had
        # the same offset.
        @session.execute_script <<~JS
          document.body.insertAdjacentHTML("beforeend", '<iframe src="/apparition/nested_frame_test" name="outer_frame" style="padding:200px">')
        JS

        @session.within_frame 'outer_frame' do
          @session.within_frame 'inner_frame' do
            log = @session.find(:css, '#log')
            @session.find(:css, '#one').click
            expect(log.text).to eq('one')
          end
        end
      end

      it 'does not wait forever for the frame to load' do
        @session.visit '/'

        expect do
          @session.within_frame('omg') {}
        end.to(raise_error do |e|
          expect(e).to be_a(Capybara::Apparition::FrameNotFound).or be_a(Capybara::ElementNotFound)
        end)
      end
    end

    # see https://github.com/teamapparition/apparition/issues/115
    it 'handles obsolete node during an attach_file' do
      @session.visit '/apparition/attach_file'
      @session.attach_file 'file', __FILE__
    end

    # it 'logs mouse event co-ordinates' do
    #   @session.visit('/')
    #   @session.find(:css, 'a').click
    #   position = JSON.load(TestSessions.logger.messages.last)['response']['position']
    #   expect(position['x']).to_not be_nil
    #   expect(position['y']).to_not be_nil
    # end

    it 'throws an error on an invalid CSS selector' do
      @session.visit '/apparition/table'
      expect { @session.find(:css, 'table tr:last') }.to raise_error(Capybara::Apparition::InvalidSelector)
      expect { @session.find(:css, 'table').find(:css, 'tr:last') }.to raise_error(Capybara::Apparition::InvalidSelector)
    end

    it 'throws an error on invalid xpath' do
      @session.visit('/apparition/with_js')
      expect { @session.find(:xpath, '#remove_me') }.to raise_error(Capybara::Apparition::InvalidSelector)
      expect { @session.find(:xpath, './/body').find('.//#remove_me') }.to raise_error(Capybara::Apparition::InvalidSelector)
    end

    it 'should submit form' do
      @session.visit('/apparition/send_keys')
      @session.find(:css, '#without_submit_button').trigger('submit')
      expect(@session.find(:css, '#without_submit_button input').value).to eq('Submitted')
    end

    context 'whitespace tests' do
      before do
        @session.visit '/apparition/filter_text_test'
      end

      it 'gets text' do
        expect(@session.find(:css, '#foo').text).to eq 'foo'
      end

      it 'gets text stripped whitespace' do
        expect(@session.find(:css, '#bar').text).to eq 'bar'
      end

      it 'gets text and retains relevant nbsp and whistpace' do
        expect(@session.find(:css, '#baz').text).to eq ' baz    '
      end

      it 'gets text and retains releveant nbsp and unicode whitespace' do
        expect(@session.find(:css, '#qux').text).to eq '  　 qux 　  '
      end
    end

    context 'supports accessing element properties' do
      before do
        @session.visit '/apparition/attributes_properties'
      end

      it 'gets property innerHTML' do
        expect(@session.find(:css, '.some_other_class').native.property('innerHTML')).to eq '<p>foobar</p>'
      end

      it 'gets property outerHTML' do
        expect(@session.find(:css, '.some_other_class').native.property('outerHTML')).to eq '<div class="some_other_class"><p>foobar</p></div>'
      end

      it 'gets non existent property' do
        expect(@session.find(:css, '.some_other_class').native.property('does_not_exist')).to eq nil
      end
    end

    it 'allows access to element attributes' do
      @session.visit '/apparition/attributes_properties'
      @session.find(:css, '#my_link')
      expect(@session.find(:css, '#my_link').native.attributes).to eq(
        'href' => '#', 'id' => 'my_link', 'class' => 'some_class', 'data' => 'rah!'
      )
    end

    it 'knows about its parents' do
      @session.visit '/apparition/simple'
      parents = @session.find(:css, '#nav').native.parents
      expect(parents.map(&:tag_name)).to eq %w[li ul body html]
    end

    context 'SVG tests' do
      before do
        @session.visit '/apparition/svg_test'
      end

      it 'gets text from tspan node' do
        expect(@session.find(:css, 'tspan').text).to eq 'svg foo'
      end
    end

    # setting require: [:modals] here sets the retry time to 1 second
    context 'modals', requires: [:modals] do
      before do
        @session.visit '/apparition/with_js'
      end

      it 'matches on partial strings' do
        expect do
          @session.accept_confirm '[reg.exp] (chara©+er$)' do
            @session.click_link('Open for match')
          end
        end.not_to raise_error
        expect(@session).to have_xpath("//a[@id='open-match' and @confirmed='true']")
      end

      it 'matches on regular expressions' do
        expect do
          @session.accept_confirm(/^.t.ext.*\[\w{3}\.\w{3}\]/i) do
            @session.click_link('Open for match')
          end
        end.not_to raise_error
        expect(@session).to have_xpath("//a[@id='open-match' and @confirmed='true']")
      end

      it 'works with nested modals' do
        expect do
          @session.dismiss_confirm 'Are you really sure?' do
            @session.accept_confirm 'Are you sure?' do
              @session.click_link('Open check twice')
            end
          end
        end.not_to raise_error
        expect(@session).to have_xpath("//a[@id='open-twice' and @confirmed='false']")
      end
    end

    it 'can go back when history state has been pushed' do
      @session.visit('/')
      @session.execute_script('window.history.pushState({foo: "bar"}, "title", "bar2.html");')
      expect(@session).to have_current_path('/bar2.html')
      expect { @session.go_back }.not_to raise_error
      expect(@session).to have_current_path('/')
    end

    it 'can go forward when history state is used' do
      @session.visit('/')
      @session.execute_script('window.history.pushState({foo: "bar"}, "title", "bar2.html");')
      expect(@session).to have_current_path('/bar2.html')
      # don't use #go_back here to isolate the test
      @session.execute_script('window.history.go(-1);')
      expect(@session).to have_current_path('/')
      expect { @session.go_forward }.not_to raise_error
      expect(@session).to have_current_path('/bar2.html')
    end

    context 'in threadsafe mode' do
      before do
        skip 'No threadsafe mode in this version' unless Capybara.respond_to?(:threadsafe)
        Capybara::SpecHelper.reset_threadsafe(true, @session) if Capybara.respond_to?(:threadsafe)
      end

      after do
        Capybara::SpecHelper.reset_threadsafe(false, @session) if Capybara.respond_to?(:threadsafe)
      end

      it 'uses per session wait setting' do
        Capybara.default_max_wait_time = 1
        @session.config.default_max_wait_time = 2
        expect(@session.driver.send(:session_wait_time)).to eq 2
      end
    end
  end
end
