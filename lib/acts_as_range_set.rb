module ActiveRecord #:nodoc:
  module Acts #:nodoc:
    module RangeSet #:nodoc:
      def self.included(base) #:nodoc:
        base.extend(ClassMethods)
      end
      # ActsAsRangeSet allows you to store ranges of values using a single row.
      #
      # Example:
      #   class MovieStillFrame < ActiveRecord::Base
      #     acts_as_range_set :on => time, :scope => :movie_name, :precision => 0.04 # Standard for 25 fps
      #
      #     def filename_for(time)
      #        frame = "%02d" % (time.to_f.frac / 0.04) 
      #        "/movies/#{movie_name.underscore}/#{time.to_i}_#{frame}.jpg"
      #     end
      #   end
      #  
      #  @sample = MovieStillFrame.create(:movie_name => "Very Scary Movie", :time => (0..10.minutes))
      #  @sample2 = MovieStillFrame.create(:movie_name => "Very Scary Movie", :time => (10.minutes..20.minutes))
      # Note that @sample2.time now is 0..20.minutes. As will @sample after reload
      #  @sample2.filename_for(15.minutes) # => "/movies/Very Scary Movie/900_00.jpg
      #
      # And you don't have to keep 30,000 rows for each frame
      #
      # == Scoping
      #
      # Scoping allows you to select which ranges can be joint together, for
      # example with combine! method. When no scope condition is set, all
      # consecutive or overlapping ranges will be merged into one range
      # lasting from the minimal of +from_values+ to the maximum of
      # +to_values+ within these ranges. Setting +:scope => [:column1,
      # :column2, etc...]+ will allow merging only ranges with same values
      # of columns within +scope+.
      #
      # Please note, that no warranty is made for the fields that are present, but neither store range bounds or distinuguish
      # different scopes.
      #
      # == Step values
      #
      # +:precision+ option determines how far can be ranges offset to be considered as adjacent. Default value for +:precision+ is 1.
      # If range bounds are integer values, then 1..2 and 3..4 are considered adjacent, and will be merged into single 1..4 range if
      # they belong to the same scope. It's because (3 - 2) (distance) <= 1 (precision). Ranges 1..2 and 4..5 will not be merged, 
      # because there's no range that includes missing value of 3.
      #
      # If your ranges require more precision, you can override this value.
      #
      # == Caveats
      # Unfortunately, following does not work yet:
      # 
      #  class Project < ActiveRecord::Base
      #    has_many :allocated_days, :class => "DayRange"
      #  end
      #
      #  class DayRange < ActiveRecord::Base
      #    belongs_to :project
      #    acts_as_range_set :on => :day, :scope => :project_id
      #  end
      #
      #  today = Date.today
      #  @project = Projects.find(:first)
      #  @days = @project.allocated_days.find(:all, :conditions => { :day => today.beginning_of_week..today.end_of_week })
      #
      # Use the following instead:
      #
      #  @days = @project.allocated_days.for_range(today.beginning_of_week..today.end_of_week)
      #

      module ClassMethods
        # Specifies that this model stores range of values for single field
        #
        # Options are: 
        #
        # <tt>:on</tt>:: specifies a name of field which should be stored as range. Actually, it's not an option, but mandatory argument.
        # <tt>:scope</tt>:: specifies scope keys to distiguish several rangesets.
        # <tt>:precision</tt>:: specifies difference between distinguished values.
        #
        # Additionaly, two finder methods (or named scopes) are defined. One is named +for_range+,
        # and second is named by the name of range column, e.g. for_blocks if you do +acts_as_range_set :on => :block
        #
        # == Examples
        # 
        # <tt>acts_as_range_set :on => :ip</tt>
        #
        # uses +from_ip+ and +to_ip+ to store ranges, and defines method +ip+
        # as range (<tt>self["from_ip"]</tt>..<tt>self["to_ip"]</tt>). E.g. if you want to
        # have simple ip-based ban-list supporting blacklisting networks and decided to store IPs in numeric form
        #
        # <tt>acts_as_range_set :on => :block, :scope => :device_id</tt>
        #
        # uses +from_block+ and +to_block+ to store ranges of blocks on
        # several devices. Can be used as list of contigous regions of used
        # blocks on several devices.
        #
        def acts_as_range_set(options = {})
          raise "You need to specify ':on'" unless options[:on]

          class_inheritable_accessor :aars_options
          self.aars_options = {:precision => 1}.merge options
          define_method(options[:on]) do
            _from = self.class.from_column_name
            _to = self.class.to_column_name
            return nil unless self[_from] && self[_to]
            (self[_from]..self[_to])
          end

          define_method("#{options[:on]}=") do |arg|
            _from = self.class.from_column_name
            _to = self.class.to_column_name
            if arg.is_a?(Range)
              self[_from] = arg.begin
              self[_to] = arg.end
            else
              self[_from] = self[_to] = arg # Works even for nil
            end
          end

          class_eval("def self.for_#{options[:on].to_s.pluralize}(arg); for_range arg end")

          extend  ActiveRecord::Acts::RangeSet::SingletonMethods
          include ActiveRecord::Acts::RangeSet::InstanceMethods

          before_save :try_merge!
          
          named_scope :for_range, lambda { |constraint| { :conditions => construct_range_conditions(constraint) } }
        end

        # Sets the name of column which stores beginnings of ranges.
        #
        #  class ValueRange < ActiveRecord::Base
        #    acts_as_range_set    :on => :value
        #    set_from_column_name :from
        #    set_to_column_name   :to
        #  end
        def set_from_column_name(value = nil, &block)
          define_attr_method :from_column_name, value, &block
        end

        # Same as set_from_column_name, but sets the name of column which stores ends of ranges.
        def set_to_column_name(value=nil, &block)
          define_attr_method :to_column_name, value, &block
        end

        # Sets the SQL expression to calculate length of range.
        #
        #  class TimeRange < ActiveRecord::Base
        #    acts_as_range_set :on => :time
        #    set_range_length_func "TIMESTAMPDIFF(SECOND, from_time, to_time) + 1"
        #  end
        def set_range_length_func(value = nil, &block)
          define_attr_method :range_length_func, value, &block
        end

        attr_reader :range_column, :from_column_name, :to_column_name
        def range_column #:nodoc:
          self.aars_options[:on]
        end

        def from_column_name #:nodoc:
          "from_#{self.aars_options[:on]}"
        end

        def to_column_name #:nodoc:
          "to_#{self.aars_options[:on]}"
        end

        def range_length_func #:nodoc:
          "#{to_column_name} - #{from_column_name} + #{precision}"
        end
      end

      module InstanceMethods
        # Removes selected value or range from current range.
        #
        # If the result is empty set, then object is destroyed.
        #
        # If the result produces two ranges, then range of this object is
        # set to first range, and new object for another range is created.
        #
        # BEWARE: you can receive two objects as a result of this method!
        # Else the range is reduced appropriately
        def drop_range!(value_or_range)
          return unless value_or_range
          c_from, c_to, c_range = self.class.from_column_name, self.class.to_column_name, self.class.range_column
          range = value_or_range.is_a?(Range) ? value_or_range : (value_or_range..value_or_range)

          return self unless (range.include?(self[c_to]) || range.include?(self[c_from]) || self.send(c_range).include?(range))
          if range.include? self.send(c_range)
            self.send("#{c_range}=", nil)
            return new_record? ? self : self.destroy # Whoops, range exhausted!
          else
            _from  = [range.begin, self[c_from]].max
            _to = [range.end, self[c_to]].min
            
            if _from > self[c_from] && _to < self[c_to]
              other = self.class.new(self.attributes.merge({ c_from => self.class.next_range_start(_to) }))              
              self[c_to] = self.class.prev_range_end(_from)
              unless new_record?
                update
                other.save
              end
              return self, other
            elsif _from > self[c_from]
              self[c_to] = self.class.prev_range_end(_from)
            else # _to < self[c_to]
              self[c_from] = self.class.next_range_start(_to)
            end
            update unless new_record?
            return self
          end
        end

        protected
        def try_merge! #:nodoc:
          c_from = self.class.from_column_name
          c_to = self.class.to_column_name
          c_range = self.class.range_column

          if !self[c_from] || !self[c_to] 
            if self[c_from]
              self[c_to] = self[c_from]
            elsif self[c_to]
              self[c_from] = self[c_to]
            end
          end
            
          range = self.send(c_range)
          return true unless range
          aug_range = self.class.enlarge_range(range)
          conditions = append_scope_to_conditions({ self.class.range_column => aug_range })
          other_rows = self.class.find(:all, :conditions => conditions)
          other_rows.reject! { |row| row[self.class.primary_key] == self[self.class.primary_key] || !row[c_from] || !row[c_to] }
          return true if other_rows.empty?
          big_range = other_rows.map(&c_from.to_sym).min..other_rows.map(&c_to.to_sym).max
          if range.include?(big_range)
            # We overlap existing data.
            other_rows.each(&:destroy)
            return true
          else
            first = other_rows.shift
            new_from = first[c_from]
            new_to = first[c_to]
            if big_range.include?(range) # Existing data (maybe sparce) overlaps us.  This range just fills the gaps.
              new_to = big_range.end
            elsif big_range.begin <= range.begin && range.include?(self.class.next_range_start(big_range.end)) # Augmenting from right
              new_to = range.end
            elsif range.include?(self.class.prev_range_end(big_range.begin)) && big_range.end >= range.end   # Augmenting from left
              new_from = range.begin
              new_to = big_range.end
            else
              raise "My maths is wrong or dataset is corrupted. Try #{self.class.name}.compact!\n" +
                "Additional details:\nbig range\t#{big_range} (#{big_range.begin.class.name})\nrange\t\t#{range} (#{range.begin.class.name})\n\n"
            end
            other_rows.each(&:destroy)
            first.update_attributes({ c_from => new_from, c_to => new_to })
            reload_from(first)
            return false
          end
        end

        def reload_from(other_row) #:nodoc:
          self.send(:attributes=, other_row.attributes, false)
        end

        def append_scope_to_conditions(conditions) #:nodoc:
          if scope = self.class.aars_options[:scope]
            if scope.is_a?(Symbol)
              conditions[scope] = self[scope]
            else
              scope.each { |attrib| conditions[attrib] = self[attrib] }
            end
          end
          conditions
        end
      end

      module SingletonMethods
        def find(*args) #:nodoc:
          options = args.extract_options!
          if options[:conditions]
            conditions = options[:conditions]
            if conditions.is_a?(Hash)
              options[:conditions], orig_range = rewrite_range_conditions!(conditions)
            end
          end
          super(*args.push(options))
        end

        def destroy_all(conditions = nil) #:nodoc:
          if conditions.is_a?(Hash)
            conditions, range_val = rewrite_range_conditions!(conditions)
          end
          find(:all, :conditions => conditions).each { |object| range_val ? object.drop_range!(range_val) : object.destroy }
        end

        def rewrite_range_conditions!(conditions) #:nodoc:
          return [conditions, nil] unless conditions.keys.map(&:to_s).include?(range_column.to_s)
          constraint = conditions[range_column.to_sym] || conditions[range_column.to_s]
          constraints_for_range = nil
          conditions.reject! { |key, constr| key.to_sym == range_column.to_sym}
          [merge_conditions(conditions, construct_range_conditions(constraint)), constraint]
        end

        # Expand constraint value into appropriate find's condition
        def construct_range_conditions(constraint)
          if constraint.is_a?(Range)
            condition = [ "(#{from_column_name} BETWEEN :begin AND :end) OR (:begin BETWEEN #{from_column_name} AND #{to_column_name})",
                    { :begin => constraint.begin, :end => constraint.end } ]
          elsif constraint
            condition = [ "? BETWEEN #{from_column_name} AND #{to_column_name}", constraint ]
          else
            condition = [ "#{from_column_name} IS NULL AND #{to_column_name} IS NULL"]
          end
          condition
        end

        # This method searches for adjacent ranges and tries to jam them into one.
        # It is to be used after you migrated your table
        def combine!(check_overlap = true)
          if scope = self.aars_options[:scope]
            scope = scope.is_a?(Array) ? scope : [scope]
            select = "DISTINCT " + scope.map { |a| connection.quote_column_name(a) }.join(", ")
            scopes = find(:all, :select => select)
            scopes.each { |scope| combine_with_scope!(scope.attributes, check_overlap)}
          else
            combine_with_scope!(nil, check_overlap)
          end
        end

        def precision #:nodoc:
          self.aars_options[:precision]
        end

        def next_range_start(val)
          return nil unless val
          return val.end + precision if val.is_a? Range
          val + precision
        end

        def prev_range_end(val)
          return nil unless val
          return val.begin - precision if val.is_a? Range
          val - precision
        end

        def enlarge_range(range_or_val)
          return nil unless range_or_val
          return prev_range_end(range_or_val)..next_range_start(range_or_val)
        end

        protected
        def combine_with_scope!(scope_args, check_overlap) #:nodoc:
          # 1. Fix overlapping regions
          tlft = quoted_table_name
          trgt = connection.quote_table_name('rgt')
          cid = connection.quote_column_name(primary_key)
          cfrom = connection.quote_column_name(from_column_name)
          cto = connection.quote_column_name(to_column_name)
          if check_overlap
            query = "SELECT DISTINCT #{tlft}.#{cid} as lft_id FROM #{self.table_name} JOIN #{self.table_name} AS rgt"
            where = "#{tlft}.#{cid} <> #{trgt}.#{cid} AND #{tlft}.#{cfrom} < #{trgt}.#{cfrom} AND #{tlft}.#{cto} >= #{trgt}.#{cfrom}"
            if scope_args
              query += ' ON (' + scope_args.keys.map { |col| ccol = connection.quote_column_name(col); "#{tlft}.#{ccol} = #{trgt}.#{ccol}" }.join(" AND ") + ')'
              where += ' AND (' + sanitize_sql_hash(scope_args) + ')'
            end
            collisions = connection.select_all("#{query} WHERE #{where}")
            collisions.each { |row| object = self.find(row["lft_id"]); object.save }
          end
          # try to merge
          conditions = scope_args ? { :conditions => scope_args } : {}
          min_from = self.minimum(from_column_name, conditions)
          max_from = self.maximum(to_column_name, conditions)
          split_combine!(scope_args, min_from, max_from)
        end

        def split_combine!(scope, min_from, max_from) #:nodoc:
          # if pointed to single row, do nothing
          return if min_from > max_from - precision
          # if min_from..max_from & scope == empty set or single row, do nothing
          from = self.from_column_name.to_s
          to = self.to_column_name.to_s
          rng = self.range_column
          conditions = { rng  => (min_from..max_from) }
          conditions.merge!(scope) if scope
          conditions, range = rewrite_range_conditions!(conditions)

          unless range_length_func 
            # I'm sorry, but we have to do a full scan.
            find(:all, :conditions => conditions).each(&:save!)
            return
          end
          # Okay, we can check ranges inside sql connections.

          query = "SELECT SUM(#{range_length_func}) AS actually_have, MAX(#{to}) AS range_end, MIN(#{from}) AS range_begin FROM #{self.table_name}"
          query += " WHERE " + sanitize_sql_for_conditions(conditions)
          res = connection.select_all(query)
          return if res.empty?
          row = res.first
          return unless row.values.all?
          want = columns_hash[to].type_cast(row["range_end"]) - columns_hash[from].type_cast(row["range_begin"]) + 1
          have = row["actually_have"].to_f
          if (want - have).abs < precision
            # Can be compacted! Yeah!
            rows ||= find(:all, :conditions => conditions, :order => "#{from} ASC")
            return if rows.size <= 1
            range_end = rows.map(&to.to_sym).max
            winner = rows.shift
            
            update_stmt = sanitize_sql_hash_for_assignment(to => range_end)
            delete_stmt = sanitize_sql_hash_for_conditions(primary_key => rows.map { |row| row[primary_key]})
            where_stmt = sanitize_sql_hash_for_conditions(primary_key => winner[primary_key])
            transaction do
              connection.execute("DELETE FROM #{quoted_table_name} WHERE #{delete_stmt}")
              connection.execute("UPDATE #{quoted_table_name} SET #{update_stmt} WHERE #{where_stmt}")
            end
          else
            # have to split.
            return if max_from - min_from <= precision
            mid_from = min_from + (max_from - min_from) / 2
            split_combine!(scope, min_from, mid_from)
            split_combine!(scope, mid_from, max_from)
          end
        end
      end
    end
  end
end

ActiveRecord::Base.send(:include, ActiveRecord::Acts::RangeSet)

