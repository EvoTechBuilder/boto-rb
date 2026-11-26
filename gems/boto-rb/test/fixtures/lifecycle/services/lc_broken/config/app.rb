# frozen_string_literal: true

Boto.configure do |config|
  config.use Boto::BootLifecycleTest::Recorder, label: "lc_broken", probe: "LcBroken::Ping"
  config.use Boto::BootLifecycleTest::FailingStart
end
