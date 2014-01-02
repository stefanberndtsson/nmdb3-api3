if Rails.env.development?
  lib_ruby_files = Dir.glob(File.join("lib/**", "*.rb"))
  lib_reloader ||= ActiveSupport::FileUpdateChecker.new(lib_ruby_files) do
    lib_ruby_files.each do |lib_file|
      silence_warnings { require_dependency(lib_file) }
    end
  end

  ActionDispatch::Callbacks.to_prepare do
    lib_reloader.execute_if_updated
  end
end
