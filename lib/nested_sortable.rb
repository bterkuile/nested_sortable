# NestedSortable

module NestedSortable
  module Controller
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      public
      def nested_sortable_data_source_for(model, options = {})
        include NestedSortable::ExtendedController
        class <<self
          attr_reader :nested_sortable_model 
          attr_reader :nested_sortable_options 
        end
        @nested_sortable_model = model.to_s.camelize.constantize
        @nested_sortable_options = default_options_for_data_source.merge(options)
        @nested_sortable_options[:columns] ||= auto_generated_columns_option
        
        define_method(@nested_sortable_options[:action]) do
          @nested_sortable_conditions = build_conditions
          if(request.post? || request.put?)
            respond_to do |format|
              format.json do
                save_items_order
                render :json => {:success=>true}.to_json
              end
            end
          elsif(request.get?)
            respond_to do |format|
              format.json { render :json => load_items_for_data_source.to_json }
            end
          end
        end
        public @nested_sortable_options[:action]
        before_filter(lambda{|c| c.instance_variable_set('@uses_nested_sortable', true)})
      end
    end
  end
  module ExtendedController
    def self.included(base)
      base.extend(ClassMethods)
    end
    module ClassMethods
      private
      def default_options_for_data_source
        {
          :action => "order",
          # #"1 = 1" is an ugly hack to prevent an SQL error when there is no
          # condition set
          :conditions =>  "1 = 1", 
          :position_column => "position",
          :parent_column => "parent_id",
          :query_parameter_name => "nested-sortable-widget"
        }
      end

      def auto_generated_columns_option
        # The default is all the attributes for the model, except keys and FKs.
        # Columns names are written using titleize()
        @nested_sortable_model.column_names.reject do |key|  
          key.match(/(^id$)|(_id$)|(^#{@nested_sortable_options[:position_column]}$)|(^#{@nested_sortable_options[:parent_column]}$)/) 
        end.collect do |key| 
          [key.to_sym, key.to_s.titleize()] 
        end
      end
    end
    
    private
    
    def build_conditions
      conditions = self.class.nested_sortable_options[:conditions]
      if(conditions.respond_to?(:call))
        conditions.call(self)
      elsif(conditions.is_a?(Symbol))
        send(conditions)
      else
        conditions
      end
    end

    def load_items_for_data_source
      requested_first_index = params[:firstIndex].to_i || 0
      requested_count = params[:count].to_i || 0
      all_items = items_array_for_hierarchy
      total_count = self.class.nested_sortable_model.count(:all, :conditions=> @nested_sortable_conditions)
      hash_to_return = {
        :requestFirstIndex => requested_first_index,
        :columns => self.class.nested_sortable_options[:columns].collect {|e| e.last},
        :totalCount => total_count
      }

      # figures out where to start and stop displaying the items
      first_to_display, last_to_display, actual_first_index, current_position, next_position, actual_count = nil, nil, nil, 0, 0, 0
      all_items.each_with_index do |item, index|
        next_position = current_position + 1 + item[:childrenCount]
        if( first_to_display.nil?)
          if(requested_first_index == current_position)
            actual_first_index = current_position
            first_to_display = index
          elsif (next_position > requested_first_index)
            actual_first_index = next_position
            first_to_display = index + 1
          end
        end
        if(!actual_first_index.nil?)
          if( requested_count == 0)
            last_to_display = all_items.length - 1
            actual_count = next_position - actual_first_index
          elsif(last_to_display.nil? && (next_position >= actual_first_index + requested_count || next_position >= total_count))
            last_to_display = index
            actual_count = next_position - actual_first_index
          end
        end
        current_position = next_position
      end

      hash_to_return[:firstIndex] = actual_first_index
      hash_to_return[:count] = actual_count
      if(actual_count > 0)
        hash_to_return[:items] = all_items[first_to_display, last_to_display - first_to_display + 1]
      else
        hash_to_return[:items] = []
      end
      return hash_to_return

    end

    def save_items_order
      if(!params[self.class.nested_sortable_options[:query_parameter_name]].nil?)
        if(!params[self.class.nested_sortable_options[:query_parameter_name]][:items].nil? )
          # if there is only one chunk of data
          items_chunks = [params[self.class.nested_sortable_options[:query_parameter_name]]]
        else
          # more than one chunk - makes hash an into an array
          items_chunks = params[self.class.nested_sortable_options[:query_parameter_name]].sort {|a,b| a.first.to_i <=> b.first.to_i}.collect{|i| i.last}
        end
      else
        raise ArgumentError, "Invalid parameter for nested sortable data source."
      end
      items_chunks.each do |chunk|
        save_order_of_items_chunk(chunk['items'])
      end
    end

    # Builds an returns an array with the ordered items of a hierarchy and all
    # its child hierarchies. They array has the following format:
    #   [
    #     {:id => 1, :info=>["Column 1 data", "Column 2 data"], :childrenCount=>0},
    #     {
    #       :id => 2,
    #       :info=>["a", "b"],
    #       :childrenCount=>1
    #       :children=> [
    #         {:id=>3, :info=>["a", "b"], :childCount=>0}
    #       ]
    #     }
    #   ]
    # 
    def items_array_for_hierarchy(parent_id = nil, should_count = false)
      returned_items = []
      fetched_items = []
      count = 0
      self.class.nested_sortable_model.send(:with_scope, {:find=>{:conditions=> @nested_sortable_conditions } } ) do
        fetched_items = self.class.nested_sortable_model.find(
          :all, 
          :conditions=>{self.class.nested_sortable_options[:parent_column].to_sym=>parent_id}, 
          :order=>"#{self.class.nested_sortable_options[:position_column]}"
        )
      end
      fetched_items.each_with_index do |item, index|
        count += 1
        returned_items[index] = { 
          :id => item.id,
          :info => self.class.nested_sortable_options[:columns].collect do |e|
            if(e.first.respond_to?(:call))
              # lambdas can be passed as the column data, they will be called,
              # with the model object passed in as a parameter
              #e.first.call(item).to_s
              instance_exec(item, &e.first).to_s
            else
              # otherwise the column data should be a symbol with the attribute
              # name
              item.send(e.first).to_s
            end
          end
        }
        child_items, child_count = items_array_for_hierarchy(item.id, true)
        returned_items[index][:childrenCount] = child_count 
        unless child_items.empty?
          count += child_count
          returned_items[index][:children] = child_items 
        end
      end
      if(should_count)
        return returned_items, count
      else
        return returned_items
      end
    end

    # Saves the order of a continuous chunk of items, grouped in an array
    def save_order_of_items_chunk(chunk, parent_id = nil)
      chunk = chunk.collect{|i| i.last} if chunk.is_a?(Hash) #converts hash to array
      self.class.nested_sortable_model.send(:with_scope, {:find=>{:conditions=> @nested_sortable_conditions } } ) do
        current_position = 0 #default for parent_id == nil
    
        # Shifts the menu order for all the root pages after the ones we will
        # alter. current_position gets the lowest position value in the chunk.
        current_position = shift_items_after_chunk(chunk) if(parent_id.nil?)

        chunk.each do |item|
          self.class.nested_sortable_model.update(
            item['id'], 
            {
              self.class.nested_sortable_options[:position_column].to_sym => current_position,
              self.class.nested_sortable_options[:parent_column].to_sym => parent_id
            }
          )
          current_position += 1
          # saves order of children
          save_order_of_items_chunk(item['children'], item['id']) unless(item['children'].nil? || item['children'].empty?)
        end
      end
    end
    
    # Shifts the items after the chunk to make it fit properly and return the
    # position of the first item of the chunk
    def shift_items_after_chunk(chunk)
      items_ids = chunk.collect{|item| item['id']}
      these_items = self.class.nested_sortable_model.find(
        :all,
        :conditions=> {
          self.class.nested_sortable_options[:parent_column].to_sym=> nil, 
          :id=>items_ids
        }, 
        :order=>"#{self.class.nested_sortable_options[:position_column]}" 
      )
          
      first_item_pos = these_items.first.send(self.class.nested_sortable_options[:position_column])
      last_item_pos = these_items.last.send(self.class.nested_sortable_options[:position_column])
          
      first_item_after = self.class.nested_sortable_model.find(
        :first,
        :conditions=> "#{self.class.nested_sortable_options[:parent_column]} IS NULL AND #{self.class.nested_sortable_options[:position_column]} > #{last_item_pos} ",
        :order=>"#{self.class.nested_sortable_options[:position_column]}" 
      )
          
      unless(first_item_after.nil?)
        first_item_after_pos = first_item_after.send(self.class.nested_sortable_options[:position_column])
        delta = first_item_pos + chunk.length - first_item_after_pos
        unless(delta == 0)
          delta_with_oper = (delta > 0)? "+ #{delta.abs.to_s}" : "- #{delta.abs.to_s}"
          self.class.nested_sortable_model.update_all(
            "#{self.class.nested_sortable_options[:position_column]} = #{self.class.nested_sortable_options[:position_column]} #{delta_with_oper}",
            "#{self.class.nested_sortable_options[:parent_column]} IS NULL AND #{self.class.nested_sortable_options[:position_column]} > #{last_item_pos}"
          ) 
        end
      end
      return first_item_pos
    end
  end
end
