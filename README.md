# Apparition - A Chrome driver for Capybara #

[![Build Status](https://secure.travis-ci.org/twalpole/apparition.svg)](http://travis-ci.org/twalpole/apparition)

Apparition is a driver for [Capybara](https://github.com/teamcapybara/capybara). It allows you to
run your Capybara tests in the Chrome browser via CDP (no selenium or chromedriver needed) in a headless or
headed configuration. It started as a fork of Poltergeist and attempts to maintain as much compatibility
with the Poltergeist API as possible.  Implementing the `capybara-webkit` specific driver methods has also begun.

## Getting help ##

Questions should be posted [on Stack
Overflow, using the 'capybara' tag](http://stackoverflow.com/questions/tagged/capybara) and mentioning
you are using the apparition driver.

Bug reports should be posted [on GitHub](https://github.com/twalpole/apparition/issues) (and be sure
to read the bug reporting guidance below).

## Installation ##

Add either

``` ruby
gem 'apparition'
```

or

``` ruby
gem 'apparition', github: 'twalpole/apparition'
```

to your Gemfile and run `bundle install`.

In your test setup add:

``` ruby
require 'capybara/apparition'
Capybara.javascript_driver = :apparition
```

If you were previously using the `:rack_test` driver, be aware that your app will now run in a separate thread and this can have
consequences for transactional tests. [See the Capybara README for more detail](https://github.com/teamcapybara/capybara/blob/master/README.md#transactions-and-database-setup).

## What's supported? ##

Apparition supports all Capybara features, and the following extended features:

* `page.status_code`
* `page.response_headers`
* `page.driver.render_base64(format, options)`
* `page.driver.scroll_to(left, top)`
* `page.driver.basic_authorize(user, password)`
* `page.driver.set_proxy(host, port, type, user, password, bypass: [bypass list passed to chrome])`
* cookie handling
* extra headers

There are some additional features:

### Taking screenshots with some extensions ###

You can grab screenshots of the page at any point by calling
`save_screenshot('/path/to/file.png')`.

By default, only the viewport will be rendered (the part of the page that is in
view). To render the entire page, use `save_screenshot('/path/to/file.png',
full: true)`.

You also have an ability to render selected element. Pass option `selector` with
any valid CSS element selector to make a screenshot bounded by that element
`save_screenshot('/path/to/file.png', selector: '#id')`.

If the desired image format is not identifiable from the filename passed you can
also pass in a `format:` option with accepable values being `:png` or `:jpeg`

If, for some reason, you need a base64 encoded screenshot you can simply call
`render_base64` which will return your encoded image. Additional options are the
same as for `save_screenshot`.

### Clicking precise coordinates ###

Sometimes its desirable to click a very specific area of the screen. You can accomplish this with
`page.driver.click(x, y)`, where x and y are the screen coordinates.

### Remote debugging (not yet implemented) ###

If you use the `:inspector => true` option (see below), remote debugging
will be enabled.

When this option is enabled, you can insert `page.driver.debug` into
your tests to pause the test and launch a browser which gives you the
WebKit inspector to view your test run with.

You can register this debugger driver with a different name and set it
as the current javascript driver. By example, in your helper file:

```ruby
Capybara.register_driver :apparition_debug do |app|
  Capybara::Apparition::Driver.new(app, :inspector => true)
end
# Capybara.javascript_driver = :apparition
Capybara.javascript_driver = :apparition_debug
```

[Read more
here](https://www.jonathanleighton.com/articles/2012/poltergeist-0-6-0/)

### Manipulating request headers ###

You can manipulate HTTP request headers with these methods:

``` ruby
page.driver.headers # => {}
page.driver.headers = { "User-Agent" => "Apparition" }
page.driver.add_headers("Referer" => "https://example.com")
page.driver.headers # => { "User-Agent" => "Apparition", "Referer" => "https://example.com" }
```

Notice that `headers=` will overwrite already set headers. You should use
`add_headers` if you want to add a few more. These headers will apply to all
subsequent HTTP requests (including requests for assets, AJAX, etc). They will
be automatically cleared at the end of the test. You have ability to set headers
only for the initial request:

``` ruby
page.driver.headers = { "User-Agent" => "Apparition" }
page.driver.add_header("Referer", "http://example.com", permanent: false)
page.driver.headers # => { "User-Agent" => "Apparition", "Referer" => "http://example.com" }
visit(login_path)
page.driver.headers # => { "User-Agent" => "Apparition" }
```

This way your temporary headers will be sent only for the initial request, and related 30x redirects. All
subsequent request will only contain your permanent headers. If the temporary
headers should not be sent on related 30x redirects, specify `permanent: :no_redirect`.

### Inspecting network traffic ###

You can inspect the network traffic (i.e. what resources have been
loaded) on the current page by calling `page.driver.network_traffic`.
This returns an array of request objects. A request object has a
`response_parts` method containing data about the response chunks.

You can inspect requests that were blocked by a whitelist or blacklist
by calling `page.driver.network_traffic(:blocked)`. This returns an array of
request objects. The `response_parts` portion of these requests will always
be empty.

Please note that network traffic is not cleared when you visit new page.
You can manually clear the network traffic by calling `page.driver.clear_network_traffic`
or `page.driver.reset`

### Manipulating cookies ###

The following methods are used to inspect and manipulate cookies:

* `page.driver.cookies` - a hash of cookies accessible to the current
  page. The keys are cookie names. The values are `Cookie` objects, with
  the following methods: `name`, `value`, `domain`, `path`, `secure?`,
  `httponly?`, `samesite`, `expires`.
* `page.driver.set_cookie(name, value, options = {})` - set a cookie.
  The options hash can take the following keys: `:domain`, `:path`,
  `:secure`, `:httponly`, `:samesite`, `:expires`. `:expires` should be a
  `Time` object.
* `page.driver.remove_cookie(name)` - remove a cookie
* `page.driver.clear_cookies` - clear all cookies

## Customization ##

You can customize the way that Capybara sets up Apparition via the following code in your
test setup:

``` ruby
Capybara.register_driver :apparition do |app|
  Capybara::Apparition::Driver.new(app, options)
end
```

`options` is a hash of options. The following options are supported:

*   `:headless` (Boolean) - When false, run the browser visibly
*   `:remote` (Boolean) - When true, connect to remote browser instead of starting locally (see [below](#Remote Chrome Driver))
*   `:debug` (Boolean) - When true, debug output is logged to `STDERR`.
*   `:logger` (Ruby logger object or any object responding to `puts`) - When present, debug output is written to this object
*   `:browser_logger` (`IO` object) - This is where your `console.log` statements will show up. Default: `STDOUT`
*   `:timeout` (Numeric) - The number of seconds we'll wait for a response
    when communicating with Chrome. Default is 30.
*   `:inspector` (Boolean, String) - See 'Remote Debugging', above.
*   `:js_errors` (Boolean) - When false, JavaScript errors do not get re-raised in Ruby.
*   `:window_size` (Array) - The dimensions of the browser window in which to test, expressed
    as a 2-element array, e.g. [1024, 768]. Default: [1024, 768]
*   `:screen_size` (Array) - The dimensions the window size will be set to when Window#maximize is called in headless mode.  Expressed
    as a 2-element array, e.g. [1600, 1200]. Default: [1366, 768]
*   `:extensions` (Array) - An array of JS files to be preloaded into
    the browser. Useful for faking or mocking APIs.
*   `:url_blacklist` (Array) - Default session url blacklist - expressed as an array of strings to match against requested URLs.
*   `:url_whitelist` (Array) - Default session url whitelist - expressed as an array of strings to match against requested URLs.
*   `:ignore_https_errors` (Boolean) - Ignore certificate errors when connecting to https URLs.
*   `:browser_options` (Hash) - Extra command line options to pass to Chrome when starting
*   `:skip_image_loading` (Boolean) - Don't load images

### Remote Chrome Driver ###
Apparition can connect to already running instance of chrome. 
Remote mode is useful when running tests in CI and chrome is available as separate docker container.

In order to use remote browser - set up apparition in the following way:
```ruby
Capybara.register_driver :apparition do |app|
  browser_options = { 'remote-debugging-address' => '127.0.0.1', 'remote-debugging-port' => 9999 }
  Capybara::Apparition::Driver.new(app, remote: true, browser_options: browser_options)
end
```

### Linux Server Configuration
In order to use Apparition on a Linux server, you need to install the chrome binary and
set certain `:browser_options`.

##### Install Chrome
```
wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo apt install -f ./google-chrome-stable_current_amd64.deb
```

#### Browser Options
```
Capybara.register_driver :apparition do |app|
  Capybara::Apparition::Driver.new(app, browser_options: { 'no-sandbox' => nil, 'disable-web-security' => nil, 'disable-features' => 'VizDisplayCompositor' })
end
```

This will enable your scripts to visit remote websites.

### URL Blacklisting & Whitelisting ###
Apparition supports URL blacklisting, which allows you
to prevent scripts from running on designated domains:

```ruby
page.driver.browser.url_blacklist = ['http://www.example.com']
```

and also URL whitelisting, which allows scripts to only run
on designated domains:

```ruby
page.driver.browser.url_whitelist = ['http://www.example.com']
```

If you are experiencing slower run times, consider creating a
URL whitelist of domains that are essential or a blacklist of
domains that are not essential, such as ad networks or analytics,
to your testing environment.

### Emulating a mobile device ###

Desktop Chrome often won't let you set the window width narrower than 500px
without also enabling mobile emulation, even when Chrome appears to accept the
width.

To test with mobile widths, it's necessary to enable mobile emulation via
CDP with all the required parameters.

```ruby
nexus_5_metrics = {
  mobile: true,
  screenWidth: 412,
  screenHeight: 660,
  width: 412,
  height: 660,
  positionX: 0,
  positionY: 0,

  scale: 1,
  deviceScaleFactor: 2.625,
  screenOrientation: {
    angle: 0,
    type: "portraitPrimary",
  },
}

page.driver.browser.current_page.command(
  "Emulation.setDeviceMetricsOverride",
  **nexus_5_metrics,
)

page.driver.browser.current_page.command(
  "Emulation.setTouchEmulationEnabled",
  { enabled: true },
)
```

These settings put Chrome in mobile emulation mode in the same fashion as
enabling the emulation mode from the developer tools.

### Timing problems ###

Sometimes tests pass and fail sporadically. This is often because there
is some problem synchronising events properly. It's often
straightforward to verify this by adding `sleep` statements into your
test to allow sufficient time for the page to settle.

If you have these types of problems, read through the [Capybara
documentation on asynchronous
JavaScript](https://github.com/teamcapybara/capybara#asynchronous-javascript-ajax-and-friends)
which explains the tools that Capybara provides for dealing with this.

### Filing a bug ###

If you can provide specific steps to reproduce your problem, or have
specific information that might help track down the problem, then please file a bug on Github.

Include as much information as possible. For example:

* Specific steps to reproduce where possible (failing tests are even
  better)
* The output obtained from running Apparition with `:debug` turned on or ENV['DEBUG'] set
* Screenshots
* Stack traces if there are any Ruby on JavaScript exceptions generated
* The Apparition, Capybara, and Chrome version numbers used
* The operating system name and version used

## Changes ##

Version history and a list of next-release features and fixes can be found in
the [changelog](CHANGELOG.md).

## License ##

Copyright (c) 2019 Thomas Walpole

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
