require File.dirname(__FILE__) + '/spec_helper'

class ActsAsRangeSet < ActiveRecord::Base
  set_table_name 'range_checks'
  acts_as_range_set :on => :value
end

class HeavyActsAsRangeSet < ActiveRecord::Base
  set_from_column_name :range_from
  set_to_column_name   :range_to
  
  acts_as_range_set :on => :range, :scope => :range_name
  # You should check that with MySQL
  # Then the correct way will be
  # set_range_length_func "TIMESTAMPDIFF(SECOND, range_from, range_to)"
  set_range_length_func nil
end

describe ActsAsRangeSet, "top-level class methods" do
  it "should include ActiveRecord::Acts::RangeSet" do
    ActsAsRangeSet.should include(ActiveRecord::Acts::RangeSet)
    HeavyActsAsRangeSet.should include(ActiveRecord::Acts::RangeSet)
  end
  
  it "should cache its options in class variable" do
    options = ActsAsRangeSet.aars_options
    options.should have_key(:on)
    heavy_options = HeavyActsAsRangeSet.aars_options
    [:on, :scope].each { |key| heavy_options.keys.should include(key) }
    heavy_options[:scope].should == :range_name
  end
  
  it "should define accessor from_column_name" do
    ActsAsRangeSet.from_column_name.should == "from_value"
    HeavyActsAsRangeSet.from_column_name.should == "range_from"
  end
  
  it "should define accessor to_column_name" do
    ActsAsRangeSet.to_column_name.should == "to_value"
    HeavyActsAsRangeSet.to_column_name.should == "range_to"
  end
end

describe ActsAsRangeSet, "synthetic column from :on option" do
  it "should return range from..to" do
    @range = ActsAsRangeSet.new(:from_value => 3, :to_value => 5)
    @range.value.should == (3..5)
    @day_before_yesterday = 2.days.ago
    @today = Date.today
    @other = HeavyActsAsRangeSet.new(:range_name => 'sample', :range_from => @day_before_yesterday, :range_to => @today)
    @other.range.should == (@day_before_yesterday.to_time..@today.to_time)
  end
  
  it "should set table columns from_ and to_ when set" do
    @range = ActsAsRangeSet.new(:value => 8..9)
    @range.from_value.should == 8
    @range.to_value.should == 9
    @epoch = Time.at(0)
    @unix_big_bang = HeavyActsAsRangeSet.new(:range_name => 'epic epoch', :range => (@epoch - 3)..(@epoch + 3))
    @unix_big_bang.range_from.should == @epoch - 3.second
    @unix_big_bang.range_to.should == @epoch + 3.second
  end
end

describe ActsAsRangeSet, "creating" do
  before(:each) do
    HeavyActsAsRangeSet.count.should == 0
    ActsAsRangeSet.count.should == 0
  end

  after(:each) do
    HeavyActsAsRangeSet.delete_all
    ActsAsRangeSet.delete_all
  end

  it "should create single record" do
    @simple = ActsAsRangeSet.create(:value => 3)
    @complex = HeavyActsAsRangeSet.create(:range_name => 'big range', :range => 1..10)
    ActsAsRangeSet.count.should == 1
    HeavyActsAsRangeSet.count.should == 1
    @simple.value.should == (3..3)
    @complex.range.should == (1..10)
  end

  it "should augment single record from right when possible" do
    @first = ActsAsRangeSet.create(:value => 1..2)
    ActsAsRangeSet.count.should == 1
    @second = ActsAsRangeSet.create(:value => 3..4)
    ActsAsRangeSet.count.should == 1
    @second.value.should == (1..4)
    @first.reload.value.should == (1..4)
  end

  it "should not augment single record from right in different scopes" do
    range_1 = (Time.at(1).utc..Time.at(2).utc)
    range_2 = (Time.at(3).utc..Time.at(4).utc)
    range_12 = (Time.at(1).utc..Time.at(4).utc)
    range_3 = (Time.at(4).utc..Time.at(5).utc)
    @first = HeavyActsAsRangeSet.create(:range_name => "combine me!", :range => range_1)
    HeavyActsAsRangeSet.count.should == 1
    @second = HeavyActsAsRangeSet.create(:range_name => "combine me!", :range => range_2)
    HeavyActsAsRangeSet.count.should == 1
    @second.range.should == range_12
    @third = HeavyActsAsRangeSet.create(:range_name => "do_not_combine_me!", :range => range_3)
    HeavyActsAsRangeSet.count.should == 2
    @first.reload.range.should == range_12
    @second.reload.range.should == range_12
    @third.range.should == range_3
  end

  it "should augment single record from left when possible" do
    @here = ActsAsRangeSet.create(:value => 42..44)
    @there = ActsAsRangeSet.create(:value => 41..42)
    ActsAsRangeSet.count.should == 1
    @there.should == @here.reload
    @there.value.should == (41..44)
  end

  it "should not augment single record from left in different scopes" do
    galaxy_ranges = "in a galaxy far far away"
    last_year = 1.year.ago
    last_year_rng = (last_year.beginning_of_year.utc..last_year.end_of_year.utc)
    before_that = ((last_year_rng.begin - 1.year)..last_year_rng.begin)

    prehistoric = (3.years.ago.utc..(before_that.begin + 13.days))
    @long_long_time_ago = HeavyActsAsRangeSet.create(:range_name => galaxy_ranges, :range => last_year_rng)
    @rise_of_empire = HeavyActsAsRangeSet.create(:range_name => galaxy_ranges, :range => before_that)
    HeavyActsAsRangeSet.count.should == 1
    @rise_of_empire.range_from.should == 2.years.ago.beginning_of_year.utc
    @rise_of_empire.range_to.should == 1.year.ago.end_of_year.utc

    @prehistoric = HeavyActsAsRangeSet.create(:range_name => "Jurassic Park", :range => prehistoric)
    HeavyActsAsRangeSet.count.should == 2
    @prehistoric.range.should == prehistoric
  end

  it "should return existing record if range is already covered" do
    @first = ActsAsRangeSet.create(:value => 4..5)
    @second = ActsAsRangeSet.create(:value => 5)
    @first.attributes.should == @second.attributes

    @heavy_one = HeavyActsAsRangeSet.create(:range => (Time.now.beginning_of_year.utc..Time.now.end_of_year.utc))
    @i_never_repeat_myself = HeavyActsAsRangeSet.create(:range => (Time.now.beginning_of_month.utc..Time.now.end_of_month.utc))
    @i_never_repeat_myself.attributes.should == @heavy_one.attributes
  end

  it "should create new record if range is present but scope is different" do
    @heavy_one = HeavyActsAsRangeSet.create(:range_name => "heavy", :range => (Time.now.beginning_of_year.utc..Time.now.end_of_year.utc))
    @i_never_repeat_myself = HeavyActsAsRangeSet.create(:range_name => "dummy", :range => (Time.now.beginning_of_month.utc..Time.now.end_of_month.utc))
    HeavyActsAsRangeSet.count.should == 2
  end

  it "should fill spaces augmenting right when possible" do
    ActsAsRangeSet.create(:value => 1..3)
    ActsAsRangeSet.create(:value => 5..6)
    ActsAsRangeSet.count.should == 2
    ActsAsRangeSet.create(:value => 2..8)
    ActsAsRangeSet.count.should == 1
    ActsAsRangeSet.first.value.should == (1..8)

    start_time = Time.parse("2008-10-01 16:57 UTC")
    HeavyActsAsRangeSet.create(:range => start_time..(start_time + 3))
    HeavyActsAsRangeSet.create(:range => (start_time + 5)..(start_time + 7))
    HeavyActsAsRangeSet.count.should == 2
    HeavyActsAsRangeSet.create(:range => (start_time + 2)..(start_time + 10))
    HeavyActsAsRangeSet.count.should == 1
    HeavyActsAsRangeSet.first.range.should == (start_time..(start_time + 10))
  end
  
  it "should create new record when subranges are present but scope is different" do
    start_time = Time.parse("2008-10-01 16:57 UTC")
    HeavyActsAsRangeSet.create(:range_name => "first", :range => start_time..(start_time + 3))
    HeavyActsAsRangeSet.create(:range_name => "first", :range => (start_time + 5)..(start_time + 7))
    HeavyActsAsRangeSet.count.should == 2
    HeavyActsAsRangeSet.create(:range => (start_time + 2)..(start_time + 10))
    HeavyActsAsRangeSet.count.should == 3
  end

  it "should make single range on overlap or spaces" do
    ActsAsRangeSet.create(:value => 1..3)
    ActsAsRangeSet.create(:value => 5..7)
    ActsAsRangeSet.count.should == 2
    ActsAsRangeSet.create(:value => 3..5)
    ActsAsRangeSet.count.should == 1
    ActsAsRangeSet.first.value.should == (1..7)

    start_time = Time.parse("2008-10-01 16:57 UTC")
    HeavyActsAsRangeSet.create(:range => (start_time + 1)..(start_time + 3))
    HeavyActsAsRangeSet.create(:range => (start_time + 5)..(start_time + 7))
    HeavyActsAsRangeSet.count.should == 2
    HeavyActsAsRangeSet.create(:range => (start_time)..(start_time + 10))
    HeavyActsAsRangeSet.count.should == 1
    HeavyActsAsRangeSet.first.range.should == (start_time..(start_time + 10))
  end
  
  it "should not combine different scopes" do
    start_time = Time.parse("2008-10-01 16:57 UTC")
    HeavyActsAsRangeSet.create(:range_name => "first", :range => (start_time + 1)..(start_time + 3))
    HeavyActsAsRangeSet.create(:range_name => "first", :range => (start_time + 5)..(start_time + 7))
    HeavyActsAsRangeSet.count.should == 2
    HeavyActsAsRangeSet.create(:range => (start_time + 2)..(start_time + 10))
    HeavyActsAsRangeSet.count.should == 3
  end
end

describe ActsAsRangeSet, "data recovery" do
  before(:each) do
    ActsAsRangeSet.count.should == 0
  end
  
  after(:each) do
    ActsAsRangeSet.delete_all
  end
  
  it "should be provided by combine! method" do
    ActsAsRangeSet.should respond_to(:combine!)
    HeavyActsAsRangeSet.should respond_to(:combine!)
  end

  it "should merge overlapping ranges creeped into database" do
    @connection = ActsAsRangeSet.connection
    ["(1, 5)", "(2, 6)"].each do |values|
      @connection.execute("INSERT INTO range_checks(from_value, to_value) VALUES #{values}")
    end
    ActsAsRangeSet.count.should == 2
    ActsAsRangeSet.combine!
    ActsAsRangeSet.count.should == 1
    ActsAsRangeSet.first.value.should == (1..6)
  end
  
  it "should merge consecutive ranges creeped into database" do
    @connection = ActsAsRangeSet.connection
    ["(1, 5)", "(6, 10)"].each do |values|
      @connection.execute("INSERT INTO range_checks(from_value, to_value) VALUES #{values}")
    end
    ActsAsRangeSet.count.should == 2
    ActsAsRangeSet.combine!
    ActsAsRangeSet.count.should == 1
    ActsAsRangeSet.first.value.should == (1..10)
  end

  it "should not left ranges split…" do
    @connection = ActsAsRangeSet.connection
    ["(1, 6)", "(7, 8)", "(10, 11)"].each do |values|
      @connection.execute("INSERT INTO range_checks(from_value, to_value) VALUES #{values}")
    end
    ActsAsRangeSet.count.should == 3
    ActsAsRangeSet.combine!
    ActsAsRangeSet.count.should == 2
    ActsAsRangeSet.first.value.should == (1..8)
    ActsAsRangeSet.last.value.should == (10..11)    
  end
end

describe ActsAsRangeSet, "finding with ranges in :conditions hash" do
  before(:each) do
    HeavyActsAsRangeSet.count.should == 0
    ActsAsRangeSet.count.should == 0

    ActsAsRangeSet.create(:value => 1..3)
  end

  after(:each) do
    HeavyActsAsRangeSet.delete_all
    ActsAsRangeSet.delete_all
  end

  it "should return empty set when no records found" do
    @results = ActsAsRangeSet.find(:all, :conditions => { :value => 5 })
    @results.size.should == 0
  end

  it "should return exact match when found" do
    @results = ActsAsRangeSet.find(:all, :conditions => { :value => 1..3 })
    @results.size.should == 1
    @results.first.value.should == (1..3)
  end

  it "should return records that have subranges of given range" do
    ActsAsRangeSet.create(:value => 5..7)
    ActsAsRangeSet.create(:value => 9..11)

    @result = ActsAsRangeSet.find(:all, :conditions => { :value => 1..11 })
    @result.size.should == 3

    @result = ActsAsRangeSet.find(:all, :conditions => { :value => 6..10 })
    @result.size.should == 2
    @result.each { |row| (row.value == (5..7) || row.value == (9..11)).should == true }

    @result = ActsAsRangeSet.find(:all, :conditions => { :value => 4..8 })
    @result.size.should == 1
    @result.first.value.should == (5..7)
  end

  it "should respect other conditions" do
    time = Time.parse("2008-10-01 17:21 UTC")
    @rng = HeavyActsAsRangeSet.create(:range_name => "my_range", :range => (time..(time + 3)))
    @results = HeavyActsAsRangeSet.find(:all, :conditions => { :range => time })
    @results.size.should == 1
    @results.first.should == @rng

    @results = HeavyActsAsRangeSet.find(:all, :conditions => { :range => time + 1, :range_name => "404 Not Found" })
    @results.should be_empty
  end
end

describe ActsAsRangeSet, "range updating with #drop_range! method" do
  before(:each) do
    @range = ActsAsRangeSet.new(:value => 1..10)
    @range.should_not_receive(:destroy)
  end
  
  it "should set range to nil when range is exhausted" do
    @result = @range.drop_range!(1..10)
    @range.value.should == nil
    @range.from_value.should == nil
    @range.to_value.should == nil
    @result.should == @range
  end
  
  it "should shrink range from right when dropping results in right trim" do
    @range.drop_range!(8..12)
    @range.from_value.should == 1
    @range.to_value.should == 7
    @range.value.should == (1..7)
  end
  
  it "should shrink range from left when dropping results in left trim" do
    @range.drop_range!(-3..5)
    @range.from_value.should == 6
    @range.to_value.should == 10
    @range.value.should == (6..10)
  end
  
  it "should split range in two when dropping results in loss of continuity" do
    @range, @new_range = @range.drop_range!(5..6)
    @range.value.should == (1..4)
    @new_range.value.should == (7..10)
  end
  
  it "should duplicate all attributes when splitting" do
    tm = Time.parse '2008-10-01 18:11 UTC'
    @range = HeavyActsAsRangeSet.new(:range_name => "test range", :range => ((tm - 7)..(tm + 7)))
    @result = @range.drop_range!(tm)
    @result.should be_instance_of(Array)
    @result.first.should == @range
    @range.range_to.should == (tm - 1.second)
    @last = @result.last
    @last.range_from.should == (tm + 1.second)
    @last.range_to.should == (tm + 7.second)
  end
  
  it "should return object untouched if the ranges have no intersection" do
    @range.drop_range!(15..20)
    @range.value.should == (1..10)
  end
end

describe ActsAsRangeSet, "destroying with ranges" do
  before(:all) do
    class HeavyActsAsRangeSet
      alias :old_drop_range! :drop_range!
      def drop_range!(arg); raise "No wai!" end
    end
  end
  
  before(:each) do
    HeavyActsAsRangeSet.destroy_all
    HeavyActsAsRangeSet.count.should == 0
  end

  after(:all) do
    class HeavyActsAsRangeSet    
      alias :drop_range! :old_drop_range!
    end
  end
  
  it "should be done as usual if range is not set" do
    start = Time.parse('2008-10-03 13:54 UTC')
    HeavyActsAsRangeSet.create(:range_name => "Your range", :range => (start + 1..start + 3))
    HeavyActsAsRangeSet.create(:range_name => "Your range", :range => (start + 6..start + 7))
    HeavyActsAsRangeSet.create(:range_name => "My range", :range => (start + 1..start + 10))
    HeavyActsAsRangeSet.count.should == 3
    lambda { HeavyActsAsRangeSet.destroy_all(:range_name => "Your range")}.should_not raise_error
    HeavyActsAsRangeSet.count.should == 1
    HeavyActsAsRangeSet.first.range_name.should == "My range"
  end
  
  it "should use drop_range! if range is not set" do
    HeavyActsAsRangeSet.create(:range_name => "Your range", :range => (1..3))
    HeavyActsAsRangeSet.create(:range_name => "Your range", :range => (6..7))
    HeavyActsAsRangeSet.create(:range_name => "My range", :range => (1..10))
    HeavyActsAsRangeSet.count.should == 3
    lambda { HeavyActsAsRangeSet.destroy_all(:range_name => "Your range", :range => (2..7)) }.should raise_error("No wai!")
  end  
end
