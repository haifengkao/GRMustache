Pod::Spec.new do |s|
  s.name     = 'GRMustacheObjC'
  s.version  = '7.8.0'
  s.license  = { :type => 'MIT', :file => 'LICENSE' }
  s.summary  = 'Flexible and production-ready Mustache templates for MacOS Cocoa and iOS.'
  s.homepage = 'https://github.com/haifengkao/GRMustacheObjC'
  s.author   = { 'Hai Feng Kao' => 'haifeng@cocoaspice.in' }
  s.source   = { :git => 'https://github.com/haifengkao/GRMustacheObjC.git', :tag => s.version.to_s}
  s.source_files = 'src/classes/**/*.{h,m}'
  s.private_header_files = 'src/classes/**/*_private.h'
  s.ios.deployment_target = '10.0'
  s.osx.deployment_target = '10.10'
  s.requires_arc = false
  s.framework = 'Foundation'
  s.dependency 'JRSwizzle', '~> 1.0'
end
