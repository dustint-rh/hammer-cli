require 'csv'
if CSV.const_defined? :Reader
  # Ruby 1.8 compatible
  require 'fastercsv'
  Object.send(:remove_const, :CSV)
  CSV = FasterCSV
else
  # CSV is now FasterCSV in ruby 1.9
end

module HammerCLI::Output::Adapter

  class CSValues < Abstract

    class FieldDataWrapper
      attr_accessor :field_wrapper, :data

      def initialize(field_wrapper, data)
        @field_wrapper = field_wrapper
        @data = data
      end

      def value
        HammerCLI::Output::Adapter::CSValues.data_for_field(@field_wrapper.field, data)
      end

      def self.values(field_data_wrappers)
        field_data_wrappers.inject([]) do |row_presentation, cell|
          unless cell.field_wrapper.field.class <= Fields::Id && !@context[:show_ids]
            row_presentation << cell.value 
          end
        end
      end

      def self.headers(field_data_wrappers)
        field_data_wrappers.map(&:field_wrapper)
                .select{ |f| !(f.field.class <= Fields::Id) || @context[:show_ids] }
                  .map { |f| f.display_name }
      end

      def self.expand_collection(field, data)
        results = []
        collection_data = HammerCLI::Output::Adapter::CSValues.data_for_field(field, data)
        collection_data.each_with_index do |child_data, i|
          field.fields.each do |child_field|
            child_field_wrapper = FieldWrapper.new(child_field)
            child_field_wrapper.append_prefix(field.label)
            child_field_wrapper.append_suffix(i.to_s)
            results << FieldDataWrapper.new(child_field_wrapper, collection_data[i] || {})
          end
        end
        results
      end

      def self.collect(fields, data)
        collect_field_data(FieldWrapper.wrap(field), data)
      end

      def self.collect_field_data(field_wrappers, data)
        results = []
        field_wrappers.each do |field_wrapper|
          field = field_wrapper.field
          if field.is_a? Fields::Collection
            results = results + expand_collection(field, data)
          elsif field.is_a?(Fields::ContainerField)
            child_fields = FieldWrapper.wrap(field.fields)
            child_fields.each{ |child| child.append_prefix(field.label) }
            results = results + collect_field_data(child_fields, HammerCLI::Output::Adapter::CSValues::data_for_field(field, data))
          else
            results << FieldDataWrapper.new(field_wrapper, data)
          end
        end
        return results
      end
    end

    class FieldWrapper
      attr_accessor :name, :field

      def self.wrap(fields)
        fields.map{ |f| FieldWrapper.new(f) }
      end

      def initialize(field)
        @field = field
        @name = nil
        @prefixes = []
        @suffixes = []
        @data
      end

      def append_suffix(suffix)
        @suffixes << suffix 
      end

      def append_prefix(prefix)
        @prefixes << prefix
      end

      def prefix
        @prefixes.join("::")
      end

      def suffix 
        @suffixes.join("::")
      end

      def display_name
        result = "#{@name || @field.label}"
        result = "#{prefix}::" + result unless prefix.empty?
        result = result + "::#{suffix}" unless suffix.empty?
        result
      end
    end

    def tags
      [:flat]
    end

    def print_record(fields, record)
      require 'debugger' 
      print_collection(fields, [record].flatten(1))
    end

    def find_leaf_fields(field_wrappers)
      results = []
      field_wrappers.each do |field_wrapper|
        field = field_wrapper.field
        if field.is_a? Fields::Collection
          #do not display
        elsif field.is_a?(Fields::ContainerField)
          child_fields = FieldWrapper.wrap(field.fields)
          child_fields.each{ |child| child.append_prefix(field.label) }
          results = results + find_leaf_fields(child_fields)
        else
          results << field_wrapper
        end
      end
      return results
    end

    def format(field, value)
      formatter = @formatters.formatter_for_type(field.class)
      (formatter ? formatter.format(value) : value) || ''
    end

    def print_collection(fields, collection)
      row_data = []
      collection.each do |data|
        row_data << FieldDataWrapper.collect_field_data(FieldWrapper.wrap(fields), data)
      end
      csv_string = generate do |csv|
        # labels
        require 'debugger'
        debugger
        csv << FieldDataWrapper.headers(row_data[0])
        row_data.each do |row|
          csv << FieldDataWrapper.values(row)
        end
      end
      puts csv_string
    end

    def print_message(msg, msg_params={})
      csv_string = generate do |csv|
        id = msg_params["id"] || msg_params[:id]
        name = msg_params["name"] || msg_params[:name]

        labels = [_("Message")]
        data = [msg.format(msg_params)]

        if id
          labels << _("Id")
          data << id
        end

        if name
          labels << _("Name")
          data << name
        end

        csv << labels
        csv << data
      end
      puts csv_string
    end

    private

    def generate(&block)
      CSV.generate(
        :col_sep => @context[:csv_separator] || ',',
        :encoding => 'utf-8',
        &block
      )
    end

  end

  HammerCLI::Output::Output.register_adapter(:csv, CSValues)

end
