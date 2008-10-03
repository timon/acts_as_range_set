ActiveRecord::Schema.define(:version => 0) do
  create_table :range_checks, :force => true do |t|
    t.column :from_value, :integer
    t.column :to_value, :integer
  end
  
  create_table :heavy_acts_as_range_sets, :force => true do |t|
    t.column :range_name, :string
    t.column :range_from, :timestamp
    t.column :range_to, :timestamp
  end
end
