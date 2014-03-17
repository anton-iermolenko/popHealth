require ::File.expand_path('../../../config/environment',  __FILE__)
require 'pqri_reporter'
require 'fileutils'

namespace :pqri do

  desc 'Generate an aggregate PQRI for the currently loaded patients and measures'
  task :report, [:effective_date] do |t, args|

    raise "You must specify an effective date" unless args.effective_date
    FileUtils.mkdir_p File.join(".","tmp")

    effective_date = args.effective_date.to_i
    period_start = 3.months.ago(Time.at(effective_date)).to_i
    report_result = PQRIReporter.measure_report(period_start, effective_date)
    report_xml = PQRIReporter.render_xml(report_result)
    outfile = File.join(".","tmp","pophealth_pqri.xml")
    File.open(outfile, 'w') {|f| f.write(report_xml) }
    puts "wrote result to: #{outfile}"
  end

end

namespace :qrda do

  desc 'Generates QRDA Category 3 for specified :username'
  task :report, [:username] do |t, args|

    raise 'You must specify username' unless args.username

    user = MONGO_DB['users'].find({username: args.username}).one
    raise 'User not found' unless user

    effective_date = Time.at(user["effective_date"])
    period_start = 3.months.ago(effective_date)

    selected_measures = MONGO_DB['selected_measures'].find({username: args.username})
    selected_measure_ids = selected_measures.map { |m| m["id"] }
    measures = MONGO_DB['measures'].find({ id: {'$in' => selected_measure_ids}})

    # Ensure every measure is calculated
    measures.each do |measure|
      oid_dictionary = OidHelper.generate_oid_dictionary(measure)
      qr = QME::QualityReport.new(measure['id'], measure['sub_id'], 'effective_date' => effective_date.to_i, 'oid_dictionary' => oid_dictionary)
      qr.calculate(false) unless qr.calculated?
    end

    cat3_exporter = HealthDataStandards::Export::Cat3.new
    qrda3_report = cat3_exporter.export(measures, effective_date, period_start, effective_date )

    FileUtils.mkdir_p File.join(".","tmp")
    outfile = File.join(".","tmp", 'pophealth_qrda.xml')
    File.open(outfile, 'w') {|f| f.write(qrda3_report) }
    puts "wrote result to: #{outfile}"
  end

end
