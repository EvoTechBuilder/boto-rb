# frozen_string_literal: true

Boto.configure do |config|
  config.use Boto::BootLifecycleTest::Recorder, label: "lc_shop", probe: "LcShop::Ping"
end
