# encoding: utf-8
REPORT_FILE_PATH = "reports/rsab.xlsx"
PERMANENCY_THRESHOLD = 30

namespace :rsabtest do

  #Usage
  #Development:   bundle exec rake rsabtest:generateReport[true]
  task :generateReport, [:check] => :environment do |t,args|
    args.with_defaults(:check => "true")
    require "#{Rails.root}/lib/task_utils"
    require 'descriptive_statistics/safe'
    Rake::Task["rsabtest:checkEntries"].invoke if args.check == "true"
    
    printTitle("Generating AB Test Report")

    startDate = DateTime.new(2019,3,1) #(year,month,day)
    endDate = DateTime.new(2020,6,30)
    firstDate = endDate
    lastDate = startDate

    rsEngines = ["cq","c","q","r"]
    generatedRecommendations = {}
    acceptedRecommendations = {}
    acceptedRecommendationsTime = {}
    acceptedRecommendationsQuality = {}
    rsEngines.each do |r|
      generatedRecommendations[r] = 0
      acceptedRecommendations[r] = 0
      acceptedRecommendationsTime[r] = ([].extend(DescriptiveStatistics))
      acceptedRecommendationsQuality[r] = ([].extend(DescriptiveStatistics))
    end

    los = {}
    nLos = []
    cLOsDataset = Excursion.all.select{|e| !e.draft and !e.reviewers_qscore_loriam_int.nil?}
    cLOsDataset.each_with_index do |lo,i|
      los[lo.id] = {:id => lo.id, :title => lo.title, :quality => lo.reviewers_qscore_loriam.to_f.round(1)}
    end

    extraLOs = []
    # extraLOs = [
    #   {:id => 1143, :title => "Internet: Concepto y arquitectura", :quality => 8.3}
    # ]

    extraLOs.each do |lo|
      los[lo[:id]] = lo if los[lo[:id]].blank?
    end

    los.each do |loId,lo|
      los[loId][:times_recommended] = 0
      los[loId][:accepted_recommendations] = 0
      los[loId][:accepted_recommendations_time] = []
    end

    ActiveRecord::Base.uncached do
      TrackingSystemEntry.where(:app_id=>"ViSHRecommendations", :created_at => startDate..endDate).find_each batch_size: 1000 do |e|
        begin
          lastDate = e.created_at.to_date if e.created_at.to_date > lastDate
          firstDate = e.created_at.to_date if e.created_at.to_date < firstDate
          d = JSON(e["data"])
          if rsEngines.include?(d["rsEngine"])
            
            #Count generated recommendation
            generatedRecommendations[d["rsEngine"]] = generatedRecommendations[d["rsEngine"]] + 1

            #Count LOs recommended
            d["reclo_ids"].each do |reclo_id|
              if los[reclo_id].blank?
                nLos.push(reclo_id)
                next
              end
              los[reclo_id][:times_recommended] = los[reclo_id][:times_recommended] + 1
            end
            
            #Get tracking system entries generated by LOs visited through these recommendations
            relatedEntries = TrackingSystemEntry.where(:app_id => "ViSH Viewer", :tracking_system_entry_id => e.id, :created_at => startDate..endDate)

            #Check if recommendation was accepted

            # # Approach A: consider only one related entry (the one with max time spent)
            # selectedRelatedEntries = relatedEntries
            # if relatedEntries.length > 1
            #   #Select entry with max time
            #   maxTime = -1
            #   sre = nil
            #   relatedEntries.each do |re|
            #     begin
            #       re_d = JSON(re["data"])
            #       re_duration = re_d["duration"].to_i
            #       if re_duration > maxTime
            #         maxTime = re_duration
            #         sre = re
            #       end
            #     rescue Exception => e
            #       puts "Exception processing VV entry: " + e.message
            #     end
            #   end
            #   selectedRelatedEntries = [sre]
            # end

            # Approach B: consider all entries
            selectedRelatedEntries = relatedEntries

            selectedRelatedEntries.each do |sre|
              #Count recommendation acceptance
              acceptedRecommendations[d["rsEngine"]] = acceptedRecommendations[d["rsEngine"]] + 1

              #Time spent by the user on the recommended LO
              sre_d = JSON(sre["data"])
              sre_duration = [sre_d["duration"].to_i,2*60*60].min
              acceptedRecommendationsTime[d["rsEngine"]].push(sre_duration)

              #Quality of the recommended LO
              loId = sre_d["lo"]["id"]
              lo = los[loId.to_i]
              next if lo.nil?
              acceptedRecommendationsQuality[d["rsEngine"]].push(lo[:quality])

              #Count LO recommended
              lo[:accepted_recommendations] = lo[:accepted_recommendations] + 1

              #Count LO rec time
              lo[:accepted_recommendations_time].push(sre_duration)
            end
          else
            puts "Error: unrecognized rsEngine " + d["rsEngine"]
          end
        rescue Exception => e
          puts "Exception: " + e.message
        end
      end
    end

    nLos.uniq!
    nLos.each do |loId|
      puts "No LO with id: " + loId.to_s
    end
    
    los.each do |loId,lo|
      los[loId][:accepted_recommendations_time].push(0) if los[loId][:accepted_recommendations_time].blank?
      los[loId][:permanency_rate] = (los[loId][:accepted_recommendations_time].select{|t| t>=PERMANENCY_THRESHOLD}.length/los[loId][:accepted_recommendations_time].length.to_f*100).round(1)
    end

    puts("LOs Dataset: " + los.length.to_s)
    puts("")

    rsEngines.each do |r|
      acceptedRecommendationsTime[r].push(0) if acceptedRecommendationsTime[r].blank?
      acceptedRecommendationsQuality[r].push(0) if acceptedRecommendationsQuality[r].blank?

      puts r
      puts("Generated recommendations: '" + generatedRecommendations[r].to_s + "'")
      puts("Accepted recommendations: '" + acceptedRecommendations[r].to_s + "'")
      puts("Acceptance rate: '" + (acceptedRecommendations[r]/generatedRecommendations[r].to_f*100).round(2).to_s + "%'")
      puts("Permanency rate: '" + (acceptedRecommendationsTime[r].select{|t| t>=PERMANENCY_THRESHOLD}.length/acceptedRecommendationsTime[r].length.to_f*100).round(1).to_s + "%'")
      puts("Average time of recommendations: '" + acceptedRecommendationsTime[r].mean.round(2).to_s + "'")
      puts("Standard deviation of time of recommendations: '" + acceptedRecommendationsTime[r].standard_deviation.round(2).to_s + "'")
      puts("Average quality of recommendations: '" + acceptedRecommendationsQuality[r].mean.round(2).to_s + "'")
      puts("Standard deviation of quality of recommendations: '" + acceptedRecommendationsQuality[r].standard_deviation.round(2).to_s + "'")
      puts("")
    end

    Axlsx::Package.new do |p|
      p.workbook.add_worksheet(:name => "RS AB Test Report") do |sheet|
        rows = []
        rows << ["RS AB Test Report"]
        rows << ["Period: " + startDate.strftime("%d/%m/%Y") + " - " + endDate.strftime("%d/%m/%Y") + " (" + ((endDate-startDate).to_i+1).to_s + " days)"]
        rows << ["Entries period: " + firstDate.strftime("%d/%m/%Y") + " - " + lastDate.strftime("%d/%m/%Y") + " (" + ((lastDate - firstDate).to_i+1).to_i.to_s + " days)"]
        rows << ["RS Engine","Generated recommendations","Accepted recommendations","Acceptance rate","Permanency Rate","Time of recommendations","","Quality of recommendations",""]
        rows << ["","","","","","M","SD","M","SD"]
        rowIndex = rows.length
        
        rows += Array.new(rsEngines.length).map{|r|[]}
        rsEngines.each_with_index do |n,i|
          r = rsEngines[i]
          rows[rowIndex+i] = [r,generatedRecommendations[r],acceptedRecommendations[r],(acceptedRecommendations[r]/generatedRecommendations[r].to_f*100).round(2),(acceptedRecommendationsTime[r].select{|t| t>=PERMANENCY_THRESHOLD}.length/acceptedRecommendationsTime[r].length.to_f*100).round(1),acceptedRecommendationsTime[r].mean.round(2),acceptedRecommendationsTime[r].standard_deviation.round(2),acceptedRecommendationsQuality[r].mean.round(2),acceptedRecommendationsQuality[r].standard_deviation.round(2)]
        end

        rsEngines.each_with_index do |n,i|
          r = rsEngines[i]
          rows << []
          rows << [r]
          rows << ["Time","Q"]
          puts "Invalid data!" if acceptedRecommendationsTime[r].length != acceptedRecommendationsQuality[r].length
          
          rowIndex = rows.length
          rows += Array.new(acceptedRecommendationsTime[r].length).map{|r|[]}
          acceptedRecommendationsTime[r].each_with_index do |n,i|
            rows[rowIndex+i] = [acceptedRecommendationsTime[r][i],acceptedRecommendationsQuality[r][i]]
          end
        end

        rows << []
        rows << ["LO Dataset (N=" + los.length.to_s + ")"]
        rows << ["Title","ID","Quality","Times recommended","Accepted recommendations","Permanency rate"]
        los.each do |loId,lo|
          rows << [lo[:title],lo[:id],lo[:quality],lo[:times_recommended],lo[:accepted_recommendations],lo[:permanency_rate]]
        end

        rows.each do |row|
          sheet.add_row row
        end
      end

      p.serialize(REPORT_FILE_PATH)
    end

    puts("Task Finished. Results generated at " + REPORT_FILE_PATH)
  end

  task :checkEntries => :environment do |t,args|
    printTitle("Checking Tracking System Entries")
    Rake::Task["rsabtest:removeInvalidEntries"].invoke
    Rake::Task["trsystem:populateRelatedExcursions"].invoke
    Rake::Task["trsystem:checkEntriesOfExcursions"].invoke
    Rake::Task["trsystem:deleteEntriesOfRemovedExcursions"].invoke
    printTitle("Task finished [checkEntries]")
  end

  #Remove invalid tracking system entries for ab test. Do not use in production.
  #Usage
  #Development:   bundle exec rake rsabtest:removeInvalidEntries
  task :removeInvalidEntries => :environment do |t,args|
    printTitle("Removing invalid tracking system entries for ab test")

    entriesDestroyed = 0

    ActiveRecord::Base.uncached do
      TrackingSystemEntry.find_each batch_size: 1000 do |e|
        if TrackingSystemEntry.isUserAgentBot?(e.user_agent) or !TrackingSystemEntry.isUserAgentDesktop?(e.user_agent)
          e.delete
          entriesDestroyed += 1
        end
      end
    end

    printTitle(entriesDestroyed.to_s + " entries destroyed")
    printTitle("Task finished [removeInvalidEntries]")
  end

end