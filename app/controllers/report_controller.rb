class ReportController  < ActionController::Metal

  def cqm

    current_user = request.env['warden'].authenticate!
    raise 'Could not authenticate' unless current_user

    raise 'A zip of QRDA Cat 1 patient records is required' unless params[:cat1zip]
    raise 'Parameters are required' unless params[:generationParams]

    Atna.log(current_user.username, :query)
    Log.create(:username => current_user.username, :event => 'Requested CQM report')

    # Clean all records in database
    QueryCache.all.delete
    PatientCache.all.delete
    Record.all.delete
    Provider.all.delete

    # Import patient records into database
    file = params[:cat1zip]
    i = 0
    temp_file = Tempfile.new("patient_upload")
    File.open(temp_file.path, "wb") { |f| f.write(file.read) }

    Zip::ZipFile.open(temp_file.path) do |zipfile|
      zipfile.entries.each do |entry|
        next if entry.directory?
        xml = zipfile.read(entry.name)
        result = RecordImporter.import(xml)

        raise 'One of patient records was not successfully imported' unless result[:status] == 'success'
      end
    end

    # Read parameters
    generationParams = JSON.parse(params[:generationParams])
    period_start = Time.at(generationParams['startDate'])
    effective_date = Time.at(generationParams['endDate'])
    selected_measure_ids = generationParams['measureIds']

    # Get list of measures
    measures = MONGO_DB['measures'].find({ id: {'$in' => selected_measure_ids.map { |mId| mId.upcase }}}) #Measure Ids are stored in uppercase

    # Ensure every measure is calculated
    measures.each do |measure|
      oid_dictionary = OidHelper.generate_oid_dictionary(measure)
      qr = QME::QualityReport.new(measure['id'], measure['sub_id'], 'effective_date' => effective_date.to_i, 'oid_dictionary' => oid_dictionary)
      qr.calculate(false) unless qr.calculated?
    end

    # Export Cat 3 report
    cat3_exporter = HealthDataStandards::Export::Cat3.new
    qrda3_report = cat3_exporter.export(measures, effective_date, period_start, effective_date )

    # Return it as response
    self.response_body = qrda3_report
    self.content_type = "application/xml"
  end

end