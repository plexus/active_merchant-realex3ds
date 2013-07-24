require 'equivalent-xml'

def assert_equal_xml(str1, str2, message = nil)
  assert EquivalentXml.equivalent?(str1, str2), message || "XML not equal, expected \"#{str2.inspect}\" but got \"#{str1.inspect}\""
end
