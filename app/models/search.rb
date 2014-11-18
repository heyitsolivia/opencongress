# == Schema Information
#
# Table name: searches
#
#  id                :integer          not null, primary key
#  search_text       :string(255)
#  created_at        :datetime
#  search_filters    :text
#  page              :integer
#  user_id           :integer
#  search_congresses :text
#

class Search < OpenCongressModel

  #========== INCLUDES

  include SearchHelper
  include ActionView::Helpers::TextHelper
  include Elasticsearch::Model

  #========== CONSTANTS

  SEARCHABLE_MODELS = %w(bill person)

  # The search filters that a user selects are stored in the database as a list of integers corresponding to
  # the order by which they appear in this list. This is done to limit unnecessary space usage.
  SEARCH_FILTERS = {
      0 => :search_bills,
      1 => :search_people,
      2 => :search_committees,
      3 => :search_industries,
      4 => :search_issues,
      5 => :search_news,
      6 => :search_blogs,
      7 => :search_commentary,
      8 => :search_comments,
      9 => :search_gossip_blog
  }

  SEARCH_FILTERS_INVERTED = SEARCH_FILTERS.invert

  #========== RELATIONS

  #----- BELONGS_TO

  belongs_to :user

  #========== CALLBACKS

  before_validation :doctor_data_for_save
  after_save :doctor_data_for_load
  after_find :doctor_data_for_load

  #========== VALIDATORS

  validates :page, numericality: { greater_than: 0 }, allow_blank: true
  validates :search_text, length: { minimum: 4, message: 'Your query must be longer than three characters!'}
  validates :search_text, length: { maximum: 255, message: 'Your query is too long (>255 characters)!'}
  validates :search_text, presence: {message: "You didn't enter anything meaningful into the search field!"}

  #========== SERIALIZERS

  serialize :search_filters, Array
  serialize :search_congresses, Array

  #========== METHODS

  #----- CLASS

  def self.reset_all_indices
    drop_all_indices
    create_all_indices
  end

  def self.drop_all_indices
    SEARCHABLE_MODELS.each do |name|
      model = name.camelize.constantize
      model.__elasticsearch__.client.indices.delete index: model.index_name rescue nil
    end
  end

  def self.create_all_indices
    SEARCHABLE_MODELS.each do |name|
      model = name.camelize.constantize
      model.import_bulk
    end
  end

  def self.elasticsearch_body(query, should_array = [], must_array = [])
    {
      query: {
        function_score: {
          query: {
            bool: {
              should: should_array,
              must: must_array
           }
          },
          functions: [
            {
              field_value_factor: {
                field: 'page_views_count',
                modifier: 'sqrt',
                factor: 0.5
              }
            }
          ],
        },
      }
    }
  end

  def self.search(query, indexes = [], limit = 25)
    prepare_search(query,indexes,limit).hits.hits.collect{|record| record._type.camelize.constantize.find(record._id) }
  end

  def self.prepare_search(query, indexes = [], limit = 25)
    should_part = SEARCHABLE_MODELS.collect{|i| i.camelize.constantize.should_search(query)}
    must_part = SEARCHABLE_MODELS.collect{|i| i.camelize.constantize.must_search(query)}
    query = {body: elasticsearch_body(query, should_part, must_part)}
    query[:indexes] = indexes if indexes.any?
    Elasticsearch::Model.client.search(query)
  end

  # Retrieves the top searched terms from the database
  #
  # @return [Relation<Search>] top searches
  def self.top_search_terms(num = 100, since = Settings.default_count_time)
    Search.find_by_sql(["SELECT LOWER(search_text) as text, COUNT(id) as count
                         FROM searches
                         WHERE created_at > ? AND LOWER(search_text) <> 'none'
                         GROUP BY LOWER(search_text) ORDER BY count DESC LIMIT ?", since.ago, num])
  end

  #----- INSTANCE

  public

  # Convenience method to get congresses from the search filters.
  #
  # @return [Array<String>] the congresses numbers as strings
  def get_congresses
    self.search_congresses
  end

  def get_query_stripped
    prepare_tsearch_query(self.search_text.to_s)
  end

  private

  # Doctors the input data before saving to the database.
  #
  def doctor_data_for_save
    self.page = 1 if (self.page.nil? || self.page < 1)
    self.search_text = truncate(self.search_text, :length => 255)
    self.search_filters.each_with_index {|v,i| self.search_filters[i] = SEARCH_FILTERS_INVERTED[v.to_sym] if v.is_a? String  }
    self.search_congresses = ["#{Settings.default_congress}"] unless self.search_congresses.is_a? Array
  end

  # This is the reverse operation for :doctor_data_for_save whereby
  # we convert the database representation to the explicit symbol
  # representation for each search filter.
  #
  def doctor_data_for_load
    self.search_filters.each_with_index {|v,i| self.search_filters[i] = SEARCH_FILTERS[v] } rescue false
  end

end