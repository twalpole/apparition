# Version 0.6.0
Release date: Unreleased

### Added

* Support "Remote" Chrome browser

# Version 0.5.0
Release date: 2020-01-26

### Added

* Support :drop_modifiers option in `#drag_to`
* Support setting range input

### Fixed

* Ruby 2.7 keyword arguments warnings
* Error in visibility JS atom [Stefan Wienert]
* Issue with request headers [dabrowt1]

# Version 0.4.0
Release date: 2019-07-15

### Added

* Node#rect added to support spatial filters
* Support for Capybaras `w3c_click_offset` settomg
* Support setting color inputs

### Fixed

* No longer hangs starting the browser with JRuby
* ValidityState objects can now be returned from the browser
* Headers now returned correctly
* Drag type detection improved
* Mouse button status tracked correctly through actions
* Clicking on a link that splits across multiple lines now works
* Correctly handle JS exceptions that don't provide a stacktrace

# Version 0.3.0
Release date: 2019-05-28

### Added

* Node#obscured? now supports use in nested frames

### Changed

* Click is no longer used to focus most form fields to behave more like the selenium driver
* Removed backports gem requirement

# Version 0.2.0
Release date: 2019-05-17

### Added

* Windows chrome location detection
* Node#obscured? to support the new Capybara obscured filter
* Node#drop to support the new Capybara drop functionality currently in Capybara master

### Fixed

* Node#set passes options to set_text
* :return added as alias of :enter key
* correct signal passed to shutdown Chrome

# Version 0.1.0
Release date: 2019-02-05

### Status

* All planned Poltergeist tests passing
