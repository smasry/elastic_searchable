require 'active_record'
require 'after_commit'
require 'backgrounded'
require 'elastic_searchable/queries'
require 'elastic_searchable/callbacks'
require 'elastic_searchable/index'

module ElasticSearchable
  module ActiveRecordExtensions
    attr_accessor :elastic_options

    # Valid options:
    # :index (optional) configure index to store data in.  default to ElasticSearchable.default_index
    # :type (optional) configue type to store data in.  default to model table name
    # :index_options (optional) configure index properties (ex: tokenizer)
    # :mapping (optional) configure field properties for this model (ex: skip analyzer for field)
    # :if (optional) reference symbol/proc condition to only index when condition is true 
    # :unless (optional) reference symbol/proc condition to skip indexing when condition is true
    # :json (optional) configure the json document to be indexed (see http://api.rubyonrails.org/classes/ActiveModel/Serializers/JSON.html#method-i-as_json for available options)
    #
    # Available callbacks:
    # after_index
    # called after the object is indexed in elasticsearch
    # (optional) :on => :create/:update can be used to only fire callback when object is created or updated
    #
    # after_percolate
    # called after object is indexed in elasticsearch
    # only fires if the update index call returns a non-empty set of registered percolations
    # use the "percolations" instance method from within callback to inspect what percolations were returned
    def elastic_searchable(options = {})
      options.symbolize_keys!
      self.elastic_options = options

      extend ElasticSearchable::Indexing::ClassMethods
      extend ElasticSearchable::Queries

      include ElasticSearchable::Indexing::InstanceMethods
      include ElasticSearchable::Callbacks::InstanceMethods

      backgrounded :update_index_on_create => ElasticSearchable::Callbacks.backgrounded_options, :update_index_on_update => ElasticSearchable::Callbacks.backgrounded_options
      class << self
        backgrounded :delete_id_from_index => ElasticSearchable::Callbacks.backgrounded_options
      end

      define_model_callbacks :index, :percolate, :only => :after
      after_commit :update_index_on_create_backgrounded, :if => :should_index?, :on => :create
      after_commit :update_index_on_update_backgrounded, :if => :should_index?, :on => :update
      after_commit :delete_from_index, :on => :destroy
    end
    # override default after_index callback definition to support :on option
    # see ActiveRecord::Transactions::ClassMethods#after_commit for example
    def after_index(*args, &block)
      options = args.last
      if options.is_a?(Hash) && options[:on]
        options[:if] = Array.wrap(options[:if])
        options[:if] << "@index_lifecycle == :#{options[:on]}"
      end
      set_callback(:index, :after, *args, &block)
    end
    # retuns list of percolation matches found during indexing
    def percolations
      @percolations || []
    end
  end
end

ActiveRecord::Base.send(:extend, ElasticSearchable::ActiveRecordExtensions)
