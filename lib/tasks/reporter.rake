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

    effective_date = Time.at(user["effective_date"] || Time.gm(2012, 12, 31).to_i)
    period_start = 12.months.ago(effective_date) + 1.day

    user_preferences = Preference.where({user_id: user['_id']}).first
    measures = MONGO_DB['measures'].find({ id: {'$in' => user_preferences.selected_measure_ids}})

    # Ensure every measure is calculated and export it
    measures.each do |measure|
      oid_dictionary = OidHelper.generate_oid_dictionary(measure)
      qr = QME::QualityReport.find_or_create(measure['hqmf_id'], measure['sub_id'], {'effective_date' => effective_date})
      qr.calculate({'oid_dictionary' => oid_dictionary}, false) unless qr.calculated?

      cat3_exporter = HealthDataStandards::Export::Cat3.new
      qrda3_report = cat3_exporter.export([measure], generate_header([]), effective_date, period_start, effective_date )

      target_tmp_folder = "tmp/rake/" + measure['id']
      FileUtils.mkdir_p File.join(".",target_tmp_folder)

      outfile = File.join(".",target_tmp_folder, "Report-#{measure['sub_id']}.xml")
      File.open(outfile, 'w') {|f| f.write(qrda3_report) }
      puts "wrote report cat 3: #{outfile}"

      PatientCache.where('value.measure_id' => measure['id']).where(:'value.IPP'.gt => 0).each do |patient_cache|
        patient_id = patient_cache['value']['patient_id']
        patient = Record.find_by(id: patient_id)

        patient_file_base_name = "#{patient['last']}, #{patient['first']}-#{patient_cache['value']['sub_id']}"
        outfile = File.join(".",target_tmp_folder, patient_file_base_name + '-stats.txt')
        File.open(outfile, 'w') {|f| f.write("IPP: #{patient_cache['value']['IPP']}\nDENOM: #{patient_cache['value']['DENOM']}\nNUMER: #{patient_cache['value']['NUMER']}\nDENEXCEP: #{patient_cache['value']['DENEXCEP']}\nDENEX: #{patient_cache['value']['DENEX']}") }
        puts "wrote stats to: #{outfile}"
      end
    end
  end

  def generate_header(provider)
    header = Qrda::Header.new(APP_CONFIG["cda_header"])

    header.identifier.extension = UUID.generate
    header.authors.each {|a| a.time = Time.now}
    header.legal_authenticator.time = Time.now
    header.performers << provider

    header
  end
end