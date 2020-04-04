# frozen_string_literal: true

require 'spec_helper'
require 'capybara/apparition'

module TestSessions
  Webkit = Capybara::Session.new(:apparition, TestApp)
end

# Already run elsewhere
# Capybara::SpecHelper.run_specs TestSessions::Webkit, "webkit", capybara_skip: [:download]

describe Capybara::Session do
  include AppRunner
  include Capybara::RSpecMatchers

  subject { Capybara::Session.new(:apparition, @app) }

  after { subject.reset! }

  context 'slow javascript app' do
    before(:all) do
      @app = lambda do |_env|
        body = <<-HTML
          <html><body>
            <form action="/next" id="submit_me"><input type="submit" value="Submit" /></form>
            <p id="change_me">Hello</p>

            <script type="text/javascript">
              var form = document.getElementById('submit_me');
              form.addEventListener("submit", function (event) {
                event.preventDefault();
                setTimeout(function () {
                  document.getElementById("change_me").innerHTML = 'Good' + 'bye';
                }, 500);
              });
            </script>
          </body></html>
        HTML
        [200,
         { 'Content-Type' => 'text/html', 'Content-Length' => body.length.to_s },
         [body]]
      end
    end

    before do
      Capybara.default_max_wait_time = 1
    end

    it 'waits for a request to load' do
      subject.visit('/')
      subject.find_button('Submit').click
      expect(subject).to have_content('Goodbye')
    end
  end

  context 'simple app' do
    before(:all) do
      @app = lambda do |_env|
        body = <<-HTML
          <html><body>
            <strong>Hello</strong>
            <span>UTF8文字列</span>
            <input type="button" value="ボタン" />
            <a href="about:blank">Link</a>
          </body></html>
        HTML
        [200,
         { 'Content-Type' => 'text/html; charset=UTF-8', 'Content-Length' => body.length.to_s },
         [body]]
      end
    end

    before do
      subject.visit('/')
    end

    it 'inspects nodes' do
      expect(subject.all(:xpath, '//strong').first.inspect).to include('strong')
    end

    it 'can read utf8 string' do
      utf8str = subject.all(:xpath, '//span').first.text
      expect(utf8str).to eq('UTF8文字列')
    end

    it 'can click utf8 string' do
      subject.click_button('ボタン')
    end

    it 'raises an ElementNotFound error when the selector scope is no longer valid' do
      pending 'I think this correctly raises WrongWorld'
      subject.within('//body') do
        subject.click_link 'Link'
        subject.find('//strong')
        expect { subject.find('//strong') }.to raise_error(Capybara::ElementNotFound)
      end
    end
  end

  context 'response headers with status code' do
    before(:all) do
      @app = lambda do |env|
        params = ::Rack::Utils.parse_query(env['QUERY_STRING'])
        if params['img'] == 'true'
          body = 'not found'
          return [404, { 'Content-Type' => 'image/gif', 'Content-Length' => body.length.to_s }, [body]]
        end
        body = <<-HTML
          <html>
            <body>
              <img src="?img=true">
            </body>
          </html>
        HTML
        [200,
         { 'Content-Type' => 'text/html', 'Content-Length' => body.length.to_s, 'X-Capybara' => 'WebKit' },
         [body]]
      end
    end

    it 'should get status code' do
      subject.visit '/'
      expect(subject.status_code).to eq 200
    end

    it 'should reset status code' do
      subject.visit '/'
      expect(subject.status_code).to eq 200
      subject.reset!
      expect(subject.status_code).to eq 0
    end

    it 'should get response headers' do
      subject.visit '/'
      expect(subject.response_headers['X-Capybara']).to eq 'WebKit'
    end

    it 'should reset response headers' do
      subject.visit '/'
      expect(subject.response_headers['X-Capybara']).to eq 'WebKit'
      subject.reset!
      expect(subject.response_headers['X-Capybara']).to eq nil
    end
  end

  context 'slow iframe app' do
    before do
      @app = Class.new(ExampleApp) do
        get '/' do
          <<-HTML
          <html>
          <head>
          <script>
            function hang() {
              xhr = new XMLHttpRequest();
              xhr.onreadystatechange = function() {
                if(xhr.readyState == 4){
                  document.getElementById('p').innerText = 'finished'
                }
              }
              xhr.open('GET', '/slow', true);
              xhr.send();
              document.getElementById("f").src = '/iframe';
              return false;
            }
          </script>
          </head>
          <body>
            <a href="#" onclick="hang()">Click Me!</a>
            <iframe src="about:blank" id="f"></iframe>
            <p id="p"></p>
          </body>
          </html>
          HTML
        end

        get '/slow' do
          sleep 1
          status 204
        end

        get '/iframe' do
          status 204
        end
      end
    end

    it 'should not hang the server' do
      subject.visit('/')
      subject.click_link('Click Me!')
      Capybara.using_wait_time(5) do
        expect(subject).to have_content('finished')
      end
    end
  end

  context 'session app' do
    before do
      @app = Class.new(ExampleApp) do
        enable :sessions
        get '/' do
          <<-HTML
          <html>
          <body>
            <form method="post" action="/sign_in">
              <input type="text" name="username">
              <input type="password" name="password">
              <input type="submit" value="Submit">
            </form>
          </body>
          </html>
          HTML
        end

        post '/sign_in' do
          session[:username] = params[:username]
          session[:password] = params[:password]
          redirect '/'
        end

        get '/other' do
          <<-HTML
          <html>
          <body>
            <p>Welcome, #{session[:username]}.</p>
          </body>
          </html>
          HTML
        end
      end
    end

    it 'should not start queued commands more than once' do
      subject.visit('/')
      subject.fill_in('username', with: 'admin')
      subject.fill_in('password', with: 'temp4now')
      subject.click_button('Submit')
      subject.visit('/other')
      expect(subject).to have_content('admin')
    end
  end

  context 'iframe app 1' do
    before(:all) do
      @app = Class.new(ExampleApp) do
        get '/' do
          <<-HTML
            <!DOCTYPE html>
            <html>
            <body>
              <h1>Main Frame</h1>
              <iframe src="/a" name="a_frame" width="500" height="500"></iframe>
            </body>
            </html>
          HTML
        end

        get '/a' do
          <<-HTML
            <!DOCTYPE html>
            <html>
            <body>
              <h1>Page A</h1>
              <iframe src="/b" name="b_frame" width="500" height="500"></iframe>
            </body>
            </html>
          HTML
        end

        get '/b' do
          <<-HTML
            <!DOCTYPE html>
            <html>
            <body>
              <h1>Page B</h1>
              <form action="/c" method="post">
              <input id="button" name="commit" type="submit" value="B Button">
              </form>
            </body>
            </html>
          HTML
        end

        post '/c' do
          <<-HTML
            <!DOCTYPE html>
            <html>
            <body>
              <h1>Page C</h1>
            </body>
            </html>
          HTML
        end
      end
    end

    it 'supports clicking an element offset from the viewport origin' do
      subject.visit '/'

      subject.within_frame 'a_frame' do
        subject.within_frame 'b_frame' do
          subject.click_button 'B Button'
          expect(subject).to have_content('Page C')
        end
      end
    end

    it 'raises an error if an element is obscured when clicked' do
      subject.visit('/')

      subject.execute_script(<<-JS)
        var div = document.createElement('div');
        div.style.position = 'absolute';
        div.style.left = '0px';
        div.style.top = '0px';
        div.style.width = '100%';
        div.style.height = '100%';
        document.body.appendChild(div);
      JS

      subject.within_frame('a_frame') do
        subject.within_frame('b_frame') do
          expect do
            subject.click_button 'B Button'
          end.to raise_error(Capybara::Apparition::ClickFailed)
        end
      end
    end

    it 'can swap to the same frame multiple times' do
      subject.visit('/')
      subject.within_frame('a_frame') do
        expect(subject).to have_content('Page A')
      end
      subject.within_frame('a_frame') do
        expect(subject).to have_content('Page A')
      end
    end
  end

  context 'text' do
    before(:all) do
      @app = Class.new(ExampleApp) do
        get '/' do
          <<-HTML
            <!DOCTYPE html>
            <html>
            <head></head>
            <body>
              <form>
                This is my form
                <input name="type"/>
                <input name="tagName"/>
              </form>
            </body>
            </html>
          HTML
        end
      end
    end

    it 'gets a forms text when inputs have conflicting names' do
      subject.visit('/')
      expect(subject.find(:css, 'form').text).to eq('This is my form')
    end
  end

  context 'click tests' do
    before(:all) do
      @app = Class.new(ExampleApp) do
        get '/' do
          <<-HTML
            <!DOCTYPE html>
            <html>
            <head>
            <style>
              body {
                width: 800px;
                margin: 0;
              }
              .target {
                width: 200px;
                height: 200px;
                float: left;
                margin: 100px;
              }
              #offscreen {
                position: absolute;
                left: -5000px;
              }
            </style>
            <body>
              <div id="one" class="target"></div>
              <div id="two" class="target"></div>
              <div id="offscreen"><a href="/" id="foo">Click Me</a></div>
              <form>
                <input type="checkbox" id="bar">
              </form>
              <div><a href="#"><i></i>Some link</a></div>
              <script type="text/javascript">
                var targets = document.getElementsByClassName('target');
                for (var i = 0; i < targets.length; i++) {
                  var target = targets[i];
                  target.onclick = function(event) {
                    this.setAttribute('data-click-x', event.clientX);
                    this.setAttribute('data-click-y', event.clientY);
                  };
                }
              </script>
            </body>
            </html>
          HTML
        end
      end
    end

    it 'clicks in the center of an element' do
      subject.visit('/')
      subject.find(:css, '#one').click
      expect(subject.find(:css, '#one')['data-click-x'].to_f).to be_within(1).of(199)
      expect(subject.find(:css, '#one')['data-click-y'].to_f).to be_within(1).of(199)
    end

    it 'clicks in the center of the viewable area of an element' do
      subject.visit('/')
      subject.driver.resize_window(200, 200)
      subject.find(:css, '#one').click
      expect(subject.find(:css, '#one')['data-click-x'].to_f).to be_within(1).of(149)
      expect(subject.find(:css, '#one')['data-click-y'].to_f).to be_within(1).of(99)
    end

    it 'does not raise an error when an anchor contains empty nodes' do
      subject.visit('/')
      expect { subject.click_link('Some link') }.not_to raise_error
    end

    it 'scrolls an element into view when clicked' do
      subject.visit('/')
      subject.driver.resize_window(200, 200)
      subject.find(:css, '#two').click
      expect(subject.find(:css, '#two')['data-click-x']).not_to be_nil
      expect(subject.find(:css, '#two')['data-click-y']).not_to be_nil
    end

    it 'raises an error if an element is obscured when clicked' do
      subject.visit('/')

      subject.execute_script(<<-JS)
        var two = document.getElementById('two');
        two.style.position = 'absolute';
        two.style.left = '0px';
        two.style.top = '0px';
      JS

      expect do
        subject.find(:css, '#one').click
      end.to raise_error(Capybara::Apparition::ClickFailed) { |exception|
        # The exact error message is irrelevant
        # TODO: Do we need to enable screenshot saving?
        # expect(exception.message).to match %r{Failed.*\[@id='one'\].*overlapping.*\[@id='two'\].*at position}
        # screenshot_pattern = %r{A screenshot of the page at the time of the failure has been written to (.*)}
        # expect(exception.message).to match screenshot_pattern
        # file = exception.message.match(screenshot_pattern)[1]
        # expect(File.exist?(file)).to be true
      }
    end

    it 'raises an error if a checkbox is obscured when checked' do
      subject.visit('/')

      subject.execute_script(<<-JS)
        var div = document.createElement('div');
        div.style.position = 'absolute';
        div.style.left = '0px';
        div.style.top = '0px';
        div.style.width = '100%';
        div.style.height = '100%';
        document.body.appendChild(div);
      JS

      expect { subject.check('bar') }.to raise_error(Capybara::Apparition::ClickFailed)
    end

    it 'raises an error if an element is not visible when clicked' do
      ignore_hidden_elements = Capybara.ignore_hidden_elements
      Capybara.ignore_hidden_elements = false
      begin
        subject.visit('/')
        subject.execute_script "document.getElementById('foo').style.display = 'none'"
        expect { subject.click_link 'Click Me' }.to raise_error(
          Capybara::Apparition::ClickFailed, /no visible position/
        )
      ensure
        Capybara.ignore_hidden_elements = ignore_hidden_elements
      end
    end

    it 'raises an error if an element is not in the viewport when clicked' do
      subject.visit('/')
      expect { subject.click_link 'Click Me' }.to raise_error(Capybara::Apparition::ClickFailed)
    end

    context 'with wait time of 1 second' do
      before do
        Capybara.default_max_wait_time = 1
      end

      it 'waits for an element to appear in the viewport when clicked' do
        subject.visit('/')
        subject.execute_script <<-JS
          setTimeout(function() {
            var offscreen = document.getElementById('offscreen')
            offscreen.style.left = '10px';
          }, 400);
        JS
        expect { subject.click_link 'Click Me' }.not_to raise_error
      end
    end
  end

  context 'iframe app 2' do
    before(:all) do
      @app = Class.new(ExampleApp) do
        get '/' do
          if params[:iframe] == 'true'
            redirect '/iframe'
          else
            <<-HTML
              <html>
                <head>
                  <title>Main</title>
                  <style type="text/css">
                    #display_none { display: none }
                  </style>
                </head>
                <body>
                  <iframe id="f" src="/?iframe=true"></iframe>
                  <script type="text/javascript">
                    document.write("<p id='greeting'>hello</p>");
                  </script>
                </body>
              </html>
            HTML
          end
        end

        get '/iframe' do
          headers 'X-Redirected' => 'true'
          <<-HTML
            <html>
              <head>
                <title>Title</title>
                <style type="text/css">
                  #display_none { display: none }
                </style>
              </head>
              <body>
                <script type="text/javascript">
                  document.write("<p id='farewell'>goodbye</p><iframe id='g' src='/iframe2'></iframe>");
                </script>
              </body>
            </html>
          HTML
        end

        get '/iframe2' do
          <<-HTML
            <html>
              <head>
                <title>Frame 2</title>
              </head>
              <body>
                <div>In frame 2</div>
              </body>
            </html>
          HTML
        end
      end
    end

    it 'finds frames by index' do
      subject.visit('/')
      subject.within_frame(0) do
        expect(subject).to have_xpath("//*[contains(., 'goodbye')]")
      end
    end

    it 'finds frames by id' do
      subject.visit('/')
      subject.within_frame('f') do
        expect(subject).to have_xpath("//*[contains(., 'goodbye')]")
      end
    end

    it 'finds frames by element' do
      subject.visit('/')
      frame = subject.all(:xpath, '//iframe').first
      subject.within_frame(frame) do
        expect(subject).to have_xpath("//*[contains(., 'goodbye')]")
      end
    end

    it 'switches to frame by element' do
      subject.visit('/')
      frame = subject.all(:xpath, '//iframe').first
      subject.switch_to_frame(frame)
      expect(subject).to have_xpath("//*[contains(., 'goodbye')]")
      subject.switch_to_frame(:parent)
    end

    it 'can switch back to the parent frame' do
      subject.visit('/')
      frame = subject.all(:xpath, '//iframe').first
      subject.switch_to_frame(frame)
      subject.switch_to_frame(:parent)
      expect(subject).to have_xpath("//*[contains(., 'greeting')]")
      expect(subject).not_to have_xpath("//*[contains(., 'goodbye')]")
    end

    it 'can switch to the top frame' do
      subject.visit('/')
      frame = subject.all(:xpath, '//iframe').first
      subject.switch_to_frame(frame)
      frame2 = subject.all(:xpath, '//iframe[@id="g"]').first
      subject.switch_to_frame(frame2)
      expect(subject).to have_xpath("//div[contains(., 'In frame 2')]")
      subject.switch_to_frame(:top)
      expect(subject).to have_xpath("//*[contains(., 'greeting')]")
      expect(subject).not_to have_xpath("//*[contains(., 'goodbye')]")
      expect(subject).not_to have_xpath("//div[contains(., 'In frame 2')]")
    end

    it 'raises error for missing frame by index' do
      subject.visit('/')
      expect { subject.within_frame(1) {} }
        .to raise_error(Capybara::ExpectationNotMet)
    end

    it 'raise_error for missing frame by id' do
      subject.visit('/')
      expect { subject.within_frame('foo') {} }
        .to raise_error(Capybara::ElementNotFound)
    end

    it "returns an attribute's value" do
      subject.visit('/')
      subject.within_frame('f') do
        expect(subject.all(:xpath, '//p').first['id']).to eq 'farewell'
      end
    end

    it "returns an attribute's innerHTML" do
      subject.visit('/')
      expect(subject.all(:xpath, '//body').first.native.inner_html).to match %r{<iframe.*</iframe>.*<script.*</script>.*}m
    end

    it "receive an attribute's innerHTML" do
      subject.visit('/')
      subject.all(:xpath, '//body').first.native.inner_html = 'foobar'
      expect(subject).to have_xpath("//body[contains(., 'foobar')]")
    end

    it "returns a node's text" do
      subject.visit('/')
      subject.within_frame('f') do
        expect(subject.all(:xpath, '//p').first.native.visible_text).to eq 'goodbye'
      end
    end

    it 'evaluates Javascript' do
      subject.visit('/')
      subject.within_frame('f') do
        result = subject.evaluate_script(%<document.getElementById('farewell').innerText>)
        expect(result).to eq 'goodbye'
      end
    end

    it 'executes Javascript' do
      subject.visit('/')
      subject.within_frame('f') do
        subject.execute_script(%<document.getElementById('farewell').innerHTML = 'yo'>)
        expect(subject).to have_xpath("//p[contains(., 'yo')]")
      end
    end

    it 'returns focus to parent' do
      subject.visit('/')
      original_url = subject.current_url

      subject.within_frame('f') {}

      expect(subject.current_url).to eq original_url
    end

    it 'returns the headers for the page' do
      subject.visit('/')
      subject.within_frame('f') do
        expect(subject.response_headers['X-Redirected']).to eq 'true'
      end
    end

    it 'returns the status code for the page' do
      subject.visit('/')
      subject.within_frame('f') do
        expect(subject.status_code).to eq 200
      end
    end

    it 'returns the top level browsing context text' do
      subject.visit('/')
      subject.within_frame('f') do
        expect(subject.title).to eq 'Main'
      end
    end

    it 'returns the title for the current frame' do
      subject.visit('/')
      expect(subject.driver.frame_title).to eq 'Main'
      subject.within_frame('f') do
        expect(subject.driver.frame_title).to eq 'Title'
      end
    end
  end
end
