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

    class FieldWrapper
      attr_accessor :name, :field

      def self.wrap(fields)
        fields.map{ |f| FieldWrapper.new(f) }
      end

      def initialize(field)
        @field = field
        @name = nil
        @prefixes = []
      end

      def append_prefix(prefix)
        @prefixes << prefix
      end

      def prefix
        @prefixes.join("::")
      end

      def display_name
        result = "#{@name || @field.label}"
        result = "#{prefix}::" + result unless prefix.empty?
        result
      end
    end

    def tags
      [:flat]
    end

    def print_record(fields, record)
      print_collection(find_leaf_fields(FieldWrapper.wrap(fields)), [record].flatten(1))
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

    def print_collection(field_wrappers, collection)
      csv_string = generate do |csv|
        # labels
        csv << field_wrappers.select{ |f| !(f.field.class <= Fields::Id) || @context[:show_ids] }.map { |f| f.display_name }
        # data
        collection.each do |d|
          csv << field_wrappers.map(&:field).inject([]) do |row, f|
            unless f.class <= Fields::Id && !@context[:show_ids]
              value = data_for_field(f, d)
              row << format(f,value)
            end
            row
          end
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
