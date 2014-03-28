require 'hqmf-parser'

# Merged with Measure Class from Cypress to support Cat 1 files export

# yes this is a bit ugly as it is aliasing The measure class but it
# works for now until we can truley unify these items accross applications

Measure = HealthDataStandards::CQM::Measure

class Measure

  GROUP = {'$group' => {_id: "$id", 
                        name: {"$first" => "$name"},
                        description: {"$first" => "$description"},
                        sub_ids: {'$push' => "$sub_id"},
                        subs: {'$push' => {"sub_id" => "$sub_id", "short_subtitle" => "$short_subtitle"}},
                        category: {'$first' => "$category"}}}

  CATEGORY = {'$group' => {_id: "$category",
                           measures: {'$push' => {"id" => "$_id", 
                                                  'name' => "$name",
                                                  'description' => "$description",
                                                  'subs' => "$subs",
                                                  'sub_ids' => "$sub_ids"
                                                  }}}}

  ID = {'$project' => {'category' => '$_id', 'measures' => 1, '_id' => 0}}
  
  SORT = {'$sort' => {"category" => 1}}

  index :bundle_id => 1
  index :sub_id => 1
  index :_id => 1

  def key
    "#{self['id']}#{sub_id}"
  end

  def is_cv?
    ! population_ids[QME::QualityReport::MSRPOPL].nil?
  end

  def self.installed
    Measure.order_by([["id", :asc],["sub_id", :asc]]).to_a
  end


  # Finds all measures and groups the sub measures
  # @return Array - This returns an Array of Hashes. Each Hash will represent a top level measure with an ID, name, and category.
  #                 It will also have an array called subs containing hashes with an ID and name for each sub-measure.
  def self.all_by_measure
    reduce = 'function(obj,prev) {
                if (obj.sub_id != null)
                  prev.subs.push({id : obj.id + obj.sub_id, name : obj.subtitle});
              }'

    MONGO_DB.command( :group=> {:ns=>"measures", :key => {:id=>1, :name=>1, :category=>1}, :initial => {:subs => []}, "$reduce" => reduce})["retval"]
  end

  def display_name
    "#{self['cms_id']}/#{self['nqf_id']} - #{name}"
  end


  def set_id
    self.hqmf_set_id
  end

  def measure_id
    self['id']
  end

  def continuous?
    population_ids[QME::QualityReport::MSRPOPL]
  end

  def title
    self.name
  end

  def all_data_criteria
    return @crit if @crit
    @crit = []
    self.data_criteria.each do |dc|
      dc.each_pair do |k,v|
        @crit <<HQMF::DataCriteria.from_json(k,v)
      end
    end
    @crit
  end

  def self.all
    MONGO_DB['measures'].find({})
  end

  def self.categories
    aggregate(GROUP, CATEGORY, ID, SORT)
  end

  def self.list
    aggregate({'$project' => {'id' => 1, 'sub_id' => 1, 'name' => 1, 'short_subtitle' => 1}})
  end

  private

  def self.aggregate(*pipeline)
    Mongoid.default_session.command(aggregate: 'measures', pipeline: pipeline)['result']
  end



end