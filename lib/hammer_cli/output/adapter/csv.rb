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

    def tags
      [:flat]
    end

    def print_record(fields, record)
      print_collection(find_leaf_fields(fields), [record].flatten(1))
    end

    def prefix_for_field(field, prefix)
      prefix ? prefix + "::#{field.label}" : field.label
    end

    def displayName(field, prefix)
      if(prefix)
        "#{prefix}::#{field.label}"
      else
        field.label
      end
    end

    def find_leaf_fields(fields, prefix=nil)
      results = []
      fields.each do |field|
        if field.is_a? Fields::Collection
          #do nothing
        elsif field.is_a?(Fields::ContainerField)
          results = results + find_leaf_fields(field.fields, prefix_for_field(field, prefix))
        else
          @display_for_field ||= {}
          @display_for_field[field] = displayName(field, prefix)
          results << field
        end
      end
      return results
    end

    def format(field, value)
      formatter = @formatters.formatter_for_type(field.class)
      (formatter ? formatter.format(value) : value) || ''
    end

    def print_collection(fields, collection)
      csv_string = generate do |csv|
        # labels
        csv << fields.select{ |f| !(f.class <= Fields::Id) || @context[:show_ids] }.map { |f| @display_for_field[f] }
        # data
        collection.each do |d|
          csv << fields.inject([]) do |row, f|
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
