Pod::Spec.new do |s|
  s.name     = 'GRMustacheObjC'
  s.version  = '7.4.0'
  s.license  = { :type => 'MIT', :file => 'LICENSE' }
  s.summary  = 'Flexible and production-ready Mustache templates for MacOS Cocoa and iOS.'
  s.homepage = 'https://github.com/haifengkao/GRMustache'
  s.author   = { 'Gwendal Roué' => 'gr@pierlis.com' }
  s.source   = { :git => 'https://github.com/haifengkao/GRMustache.git', :tag => 'v7.3.2' }
  s.source_files = 'src/classes/**/*.{h,m}'
  s.private_header_files = 'src/classes/**/*_private.h'
  s.ios.deployment_target = '4.3'
  s.osx.deployment_target = '10.8'
  s.requires_arc = false
  s.framework = 'Foundation'
  s.dependency 'JRSwizzle', '~> 1.0'
end
