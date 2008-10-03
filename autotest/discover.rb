$:.push(File.join(File.dirname(__FILE__), %w[.. .. rspec lib]))

Autotest.add_discovery do
    "rspec"
end

