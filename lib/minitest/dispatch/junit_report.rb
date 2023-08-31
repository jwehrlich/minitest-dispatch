require "fileutils"
require "nokogiri"

module Minitest
  module Dispatch
    # this will take a collection of test results an generate a JUnit XML report
    class JUnitReport
      def self.generate(report_path:, test_results:, class_prefix: "")
        class_prefix = "[#{class_prefix}] " unless class_prefix.empty?

        builder = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
          xml.testsuites do
            test_results.delete(:test_count)
            test_results.each do |test_suite, suite_details|
              ts_options = {
                name: "#{class_prefix}#{test_suite}",
                file: suite_details[:filepath],
                skipped: suite_details[:skipped],
                failures: suite_details[:failures],
                errors: suite_details[:errors],
                tests: suite_details[:tests],
                assertions: suite_details[:assertions],
                time: suite_details[:time]
              }
              xml.testsuite(ts_options) do
                suite_details[:test_results].each do |test_result|
                  tc_options = {
                    name: test_result.test_case,
                    file: suite_details[:filepath],
                    line: test_result.source_location[1],
                    classname: "#{class_prefix}#{test_result.test_suite}",
                    assertions: test_result.assertions,
                    time: test_result.time
                  }
                  xml.testcase(tc_options) do
                    test_result.errors.each do |error|
                      xml.error(type: error[:class], message: error[:exception]) do
                        xml.text("\n#{error[:message]}\n")
                      end
                    end

                    test_result.failures.each do |failure|
                      xml.failure(type: failure[:class], message: failure[:exception]) do
                        xml.text("\n#{failure[:message]}\n")
                      end
                    end

                    xml.skipped(type: "Minitest::Skip") if test_result.skipped?
                  end
                end
              end
            end
          end
        end

        FileUtils.mkdir_p(File.dirname(report_path))
        File.write(report_path, builder.to_xml)
        Logger.info "JUnit Report has been succesfully created: #{report_path}"
      end
    end
  end
end
