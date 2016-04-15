require 'set'

module SamsonPipelines::StageConcern

  def deploy_requires_approval?
    super || all_next_stages.any?(&:deploy_requires_approval?)
  end

  def next_stages
    Stage.find(next_stage_ids)
  end

  protected

  # Needs to find all the possible stages in case this is a pipeline of pipelines as each subsequent stage
  # could have valid next_stage_ids
  def all_next_stages
    return [] if next_stage_ids.empty?
    existing_stages = next_stage_ids.to_set
    loop do
      last_count = existing_stages.count
      existing_stages.each do |stage_id|
        existing_stages += Stage.find(stage_id).next_stage_ids.map(&:to_i).to_set
      end
      break if last_count == existing_stages.count
    end
    # if we find ourselves with ourselves in the list, we have a loop.
    # this shouldn't happen, but this will prevent it
    if existing_stages.include?(id)
      Rails.logger.error("Circular pipeline exists with stage #{id}")
      existing_stages.delete(id)
    end
    Stage.find(existing_stages.to_a)
  end

  # Ensure we don't have a circular pipeline:
  #
  # potential race-condition if 2 stages are saved at same time:
  #   stageA saved with pipelines to stageB and stageC
  #   stageC saved with pipeline to stageA   => will validate if stageA above hasn't been written to DB yet
  def valid_pipeline?(origin_id = id)
    next_stage_ids.select!(&:presence)
    if next_stage_ids.any? { |next_id| next_id.to_i == origin_id.to_i }
      errors[:base] << "Stage #{name} causes a circular pipeline with this stage"
      return false
    end

    next_stages.each do |stage|
      unless stage.valid_pipeline?(origin_id)
        errors[:base] << "Stage #{stage.name} causes a circular pipeline with this stage"
        return false
      end
    end
    true
  end

  # Make sure that this stage isn't referenced by another stage in a pipeline.
  # This will stop soft_deletion of the stage.
  def verify_not_part_of_pipeline
    project.stages.each do |s|
      if s.next_stage_ids.include?(id)
        errors[:base] << "Stage #{name} is in a pipeline from #{s.name} and cannot be deleted"
        return false
      end
    end
  end
end
