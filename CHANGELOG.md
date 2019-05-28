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
