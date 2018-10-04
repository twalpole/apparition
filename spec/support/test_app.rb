# frozen_string_literal: true

require 'capybara/spec/test_app'

class TestApp
  configure do
    set :protection, except: :frame_options
  end
  APPARITION_VIEWS  = File.dirname(__FILE__) + '/views'
  APPARITION_PUBLIC = File.dirname(__FILE__) + '/public'

  helpers do
    def requires_credentials(login, password)
      return if authorized?(login, password)

      headers['WWW-Authenticate'] = 'Basic realm="Restricted Area"'
      halt 401, "Not authorized\n"
    end

    def authorized?(login, password)
      @auth ||= Rack::Auth::Basic::Request.new(request.env)
      @auth.provided? && @auth.basic? && @auth.credentials && (@auth.credentials == [login, password])
    end
  end

  get '/apparition/test.js' do
    send_file "#{APPARITION_PUBLIC}/test.js"
  end

  get '/apparition/jquery.min.js' do
    send_file "#{APPARITION_PUBLIC}/jquery-3.2.1.min.js"
  end

  get '/apparition/jquery-ui.min.js' do
    send_file "#{APPARITION_PUBLIC}/jquery-ui-1.12.1.min.js"
  end

  get '/apparition/unexist.png' do
    halt 404
  end

  get '/apparition/status/:status' do
    status params['status']
    render_view 'with_different_resources'
  end

  get '/apparition/redirect_to_headers' do
    redirect '/apparition/headers'
  end

  get '/apparition/redirect' do
    redirect '/apparition/with_different_resources'
  end

  get '/apparition/get_cookie' do
    request.cookies['capybara']
  end

  get '/apparition/slow' do
    sleep 0.2
    'slow page'
  end

  get '/apparition/really_slow' do
    sleep 3
    'really slow page'
  end

  get '/apparition/basic_auth' do
    requires_credentials('login', 'pass')
    render_view :basic_auth
  end

  post '/apparition/post_basic_auth' do
    requires_credentials('login', 'pass')
    'Authorized POST request'
  end

  get '/apparition/cacheable' do
    cache_control :public, max_age: 60
    etag 'deadbeef'
    'Cacheable request'
  end

  get '/apparition/:view' do |view|
    render_view view
  end

  get '/apparition/arbitrary_path/:status/:remaining_path' do
    status params['status'].to_i
    params['remaining_path']
  end

protected

  def render_view(view)
    erb File.read("#{APPARITION_VIEWS}/#{view}.erb")
  end
end
