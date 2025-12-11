require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "NitroRnMacosChildProcess"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"] || "https://github.com/FreddyWhest/rn-macos-child-process"
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms = { :osx => "14.0" }  # macOS only
  s.source = { :path => "https://github.com/FreddyWhest/rn-macos-child-process.git", :tag => s.version }       # local path, or git if you publish

  s.source_files = "macos/**/*.{swift,m,mm,h}"

  s.dependency 'React'
end
