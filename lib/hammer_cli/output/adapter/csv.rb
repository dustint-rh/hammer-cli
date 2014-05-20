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

    class Cell
      attr_accessor :field_wrapper, :data

      def initialize(field_wrapper, data, formatters)
        @field_wrapper = field_wrapper
        @data = data
        @formatters = formatters
      end

      def self.create_cells(field_wrappers, data, formatters)
        results = []
        field_wrappers.each do |field_wrapper|
          field = field_wrapper.field
          if field.is_a? Fields::Collection
            results = results + expand_collection(field, data, formatters)
          elsif field.is_a?(Fields::ContainerField)
            results = results + expand_container(field, data, formatters)
          else
            results << Cell.new(field_wrapper, data, formatters)
          end
        end
        return results
      end

      def formatted_value
        formatter = @formatters.formatter_for_type(@field_wrapper.field.class)
        (formatter ? formatter.format(value) : value) || ''
      end

      def self.values(cells, context)
        cells.inject([]) do |row_presentation, cell|
          unless cell.field_wrapper.field.class <= Fields::Id && !context[:show_ids]
            row_presentation << cell.formatted_value
          end
        end
      end

      def self.headers(cells, context)
        cells.map(&:field_wrapper)
                .select{ |f| !(f.field.class <= Fields::Id) || context[:show_ids] }
                  .map { |f| f.display_name }
      end

      private

      def self.expand_collection(field, data, formatters)
        results = []
        collection_data = data_for_field(field, data)
        collection_data.each_with_index do |child_data, i|
          field.fields.each do |child_field|
            child_field_wrapper = FieldWrapper.new(child_field)
            child_field_wrapper.append_prefix(field.label)
            child_field_wrapper.append_suffix((i + 1).to_s)
            results << Cell.new(child_field_wrapper, collection_data[i] || {}, formatters)
          end
        end
        results
      end

      def self.expand_container(field, data, formatters)
        child_fields = FieldWrapper.wrap(field.fields)
        child_fields.each{ |child| child.append_prefix(field.label) }
        create_cells(child_fields, data_for_field(field, data), formatters)
      end

      def self.data_for_field(field, data)
        HammerCLI::Output::Adapter::CSValues.data_for_field(field, data)
      end

      def value
        Cell.data_for_field(@field_wrapper.field, data)
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
      print_collection(fields, [record].flatten(1))
    end

    def print_collection(fields, collection)
      row_data = []
      collection.each do |data|
        row_data << Cell.create_cells(FieldWrapper.wrap(fields), data, @formatters)
      end
      csv_string = generate do |csv|
        # labels
        csv << Cell.headers(row_data[0], @context)
        row_data.each do |row|
          csv << Cell.values(row, @context)
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
