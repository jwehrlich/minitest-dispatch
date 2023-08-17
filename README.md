# Minitest::Dispatch

This is a client/server tool that will dispatch tests to a number of consumer nodes in order to run tests distributedly. Each node can run parallel tests without the need to reload your ruby or rails project between tests files and/or test cases.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'minitest-dispatch'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install minitest-dispatch

## Usage

### Simple exmaple
*Test dispatcher node 10.10.10.1*
```bash
minitest-dispatch --mode=dispatcher --consumers=10.10.10.2,10.10.10.3 --test-files=./test
```

*Test consumer node 10.10.10.2*
```bash
minitest-dispatch --mode=consumer
```

*Test consumer node 10.10.10.3*
```bash
minitest-dispatch --mode=consumer
```

### Complex Example
```bash
minitest-dispatch --mode=dispatcher --consumers=10.10.10.2:8200,10.10.10.3:8300 --test-files=./tests/unit,./tests/integration --load-path=./tests --junit-report-path=./my_reports
```

*Test consumer node 10.10.10.2*
```bash
minitest-dispatch --mode=consumer --port=8200 --cores=2
```

*Test consumer node 10.10.10.3*
```bash
minitest-dispatch --mode=consumer --port=8300 --cores=6
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/minitest-dispatch` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jwehrlich/minitest-dispatch.

