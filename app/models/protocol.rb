# frozen_string_literal: true

class Protocol < ApplicationRecord
  ID_PREFIX = 'PT'
  include PrefixedIdModel
  SEARCHABLE_ATTRIBUTES = ['protocols.name', 'protocols.description',
                           'protocols.authors', 'protocol_keywords.name', PREFIXED_ID_SQL].freeze

  include SearchableModel
  include RenamingUtil
  include SearchableByNameModel
  include Assignable
  include PermissionCheckableModel
  include TinyMceImages

  after_update :update_user_assignments, if: -> { saved_change_to_protocol_type? && in_repository? }
  after_destroy :decrement_linked_children
  after_save :update_linked_children
  skip_callback :create, :after, :create_users_assignments, if: -> { in_module? }

  enum protocol_type: {
    unlinked: 0,
    linked: 1,
    in_repository_private: 2,
    in_repository_public: 3,
    in_repository_archived: 4
  }

  auto_strip_attributes :name, :description, nullify: false
  # Name is required when its actually specified (i.e. :in_repository? is true)
  validates :name, length: { maximum: Constants::NAME_MAX_LENGTH }
  validates :description, length: { maximum: Constants::RICH_TEXT_MAX_LENGTH }
  validates :team, presence: true
  validates :protocol_type, presence: true

  with_options if: :in_module? do |protocol|
    protocol.validates :my_module, presence: true
    protocol.validates :published_on, absence: true
    protocol.validates :archived_by, absence: true
    protocol.validates :archived_on, absence: true
  end
  with_options if: :linked? do |protocol|
    protocol.validates :added_by, presence: true
    protocol.validates :parent, presence: true
    protocol.validates :parent_updated_at, presence: true
  end

  with_options if: :in_repository? do |protocol|
    protocol.validates :name, presence: true
    protocol.validates :added_by, presence: true
    protocol.validates :my_module, absence: true
    protocol.validates :parent, absence: true
    protocol.validates :parent_updated_at, absence: true
  end
  with_options if: :in_repository_public? do |protocol|
    # Public protocol must have unique name inside its team
    protocol
      .validates_uniqueness_of :name, case_sensitive: false,
                               scope: :team,
                               conditions: lambda {
                                 where(
                                   protocol_type:
                                     Protocol
                                      .protocol_types[:in_repository_public]
                                 )
                               }
    protocol.validates :published_on, presence: true
  end
  with_options if: :in_repository_private? do |protocol|
    # Private protocol must have unique name inside its team & user scope
    protocol
      .validates_uniqueness_of :name, case_sensitive: false,
                               scope: %i(team added_by),
                               conditions: lambda {
                                 where(
                                   protocol_type:
                                     Protocol
                                       .protocol_types[:in_repository_private]
                                 )
                               }
  end
  with_options if: :in_repository_archived? do |protocol|
    # Archived protocol must have unique name inside its team & user scope
    protocol
      .validates_uniqueness_of :name, case_sensitive: false,
                               scope: %i(team added_by),
                               conditions: lambda {
                                 where(
                                   protocol_type:
                                    Protocol
                                      .protocol_types[:in_repository_archived]
                                 )
                               }
    protocol.validates :archived_by, presence: true
    protocol.validates :archived_on, presence: true
  end

  belongs_to :added_by,
             foreign_key: 'added_by_id',
             class_name: 'User',
             inverse_of: :added_protocols,
             optional: true
  belongs_to :my_module,
             inverse_of: :protocols,
             optional: true
  belongs_to :team, inverse_of: :protocols
  belongs_to :parent,
             foreign_key: 'parent_id',
             class_name: 'Protocol',
             optional: true
  belongs_to :archived_by,
             foreign_key: 'archived_by_id',
             class_name: 'User',
             inverse_of: :archived_protocols, optional: true
  belongs_to :restored_by,
             foreign_key: 'restored_by_id',
             class_name: 'User',
             inverse_of: :restored_protocols, optional: true
  has_many :linked_children,
           class_name: 'Protocol',
           foreign_key: 'parent_id'
  has_many :protocol_protocol_keywords,
           inverse_of: :protocol,
           dependent: :destroy
  has_many :protocol_keywords, through: :protocol_protocol_keywords
  has_many :steps, inverse_of: :protocol, dependent: :destroy

  def self.search(user,
                  include_archived,
                  query = nil,
                  page = 1,
                  _current_team = nil,
                  options = {})
    team_ids = Team.joins(:user_teams)
                   .where(user_teams: { user_id: user.id })
                   .distinct
                   .pluck(:id)

    module_ids = MyModule.search(user, include_archived, nil, Constants::SEARCH_NO_LIMIT)
                         .pluck(:id)

    where_str =
      '(protocol_type IN (?) AND my_module_id IN (?)) OR ' \
      '(protocol_type = ? AND protocols.team_id IN (?) AND ' \
      'added_by_id = ?) OR (protocol_type = ? AND protocols.team_id IN (?))'

    if include_archived
      where_str +=
        ' OR (protocol_type = ? AND protocols.team_id IN (?) ' \
        'AND added_by_id = ?)'
      new_query = Protocol
                  .where(
                    where_str,
                    [Protocol.protocol_types[:unlinked],
                     Protocol.protocol_types[:linked]],
                    module_ids,
                    Protocol.protocol_types[:in_repository_private],
                    team_ids,
                    user.id,
                    Protocol.protocol_types[:in_repository_public],
                    team_ids,
                    Protocol.protocol_types[:in_repository_archived],
                    team_ids,
                    user.id
                  )
    else
      new_query = Protocol
                  .where(
                    where_str,
                    [Protocol.protocol_types[:unlinked],
                     Protocol.protocol_types[:linked]],
                    module_ids,
                    Protocol.protocol_types[:in_repository_private],
                    team_ids,
                    user.id,
                    Protocol.protocol_types[:in_repository_public],
                    team_ids
                  )
    end

    new_query = new_query
                .distinct
                .joins('LEFT JOIN protocol_protocol_keywords ON ' \
                       'protocols.id = protocol_protocol_keywords.protocol_id')
                .joins('LEFT JOIN protocol_keywords ' \
                       'ON protocol_keywords.id = ' \
                       'protocol_protocol_keywords.protocol_keyword_id')
                .where_attributes_like(SEARCHABLE_ATTRIBUTES, query, options)

    # Show all results if needed
    if page == Constants::SEARCH_NO_LIMIT
      new_query
    else
      new_query.limit(Constants::SEARCH_LIMIT).offset((page - 1) * Constants::SEARCH_LIMIT)
    end
  end

  def self.viewable_by_user(user, teams)
    where(my_module: MyModule.viewable_by_user(user, teams))
      .or(where(team: teams)
            .where('protocol_type = 3 OR '\
                   '(protocol_type = 2 AND added_by_id = :user_id)',
                   user_id: user.id))
  end


  def self.filter_by_teams(teams = [])
    teams.blank? ? self : where(team: teams)
  end

  def insert_step(step, position)
    ActiveRecord::Base.transaction do
      steps.where('position >= ?', position).desc_order.each do |s|
        s.update!(position: s.position + 1)
      end
      step.position = position
      step.protocol = self
      step.save!
    end
    step
  end

  def created_by
    in_module? ? my_module.created_by : added_by
  end

  def permission_parent
    in_module? ? my_module : team
  end

  def linked_modules
    MyModule.joins(:protocols).where('protocols.parent_id = ?', id)
  end

  def linked_experiments(linked_mod)
    Experiment.where('id IN (?)', linked_mod.pluck(:experiment_id).uniq)
  end

  def linked_projects(linked_exp)
    Project.where('id IN (?)', linked_exp.pluck(:project_id).uniq)
  end

  def self.new_blank_for_module(my_module)
    Protocol.new(
      team: my_module.experiment.project.team,
      protocol_type: :unlinked,
      my_module: my_module
    )
  end

  # Deep-clone given array of assets
  def self.deep_clone_assets(assets_to_clone)
    ActiveRecord::Base.no_touching do
      assets_to_clone.each do |src_id, dest_id|
        src = Asset.find_by(id: src_id)
        dest = Asset.find_by(id: dest_id)
        dest.destroy! if src.blank? && dest.present?
        next unless src.present? && dest.present?

        # Clone file
        src.duplicate_file(dest)
      end
    end
  end

  def self.clone_contents(src, dest, current_user, clone_keywords, only_contents = false)
    dest.update(description: src.description, name: src.name) unless only_contents

    src.clone_tinymce_assets(dest, dest.team)

    # Update keywords
    if clone_keywords
      src.protocol_keywords.each do |keyword|
        ProtocolProtocolKeyword.create(
          protocol: dest,
          protocol_keyword: keyword
        )
      end
    end

    # Copy steps
    src.steps.each do |step|
      step.duplicate(dest, current_user, step_position: step.position)
    end
  end

  def in_repository_active?
    in_repository_private? || in_repository_public?
  end

  def in_repository?
    in_repository_active? || in_repository_archived?
  end

  def in_module?
    unlinked? || linked?
  end

  def linked_no_diff?
    linked? &&
      updated_at == parent_updated_at &&
      parent.updated_at == parent_updated_at
  end

  def newer_than_parent?
    linked? && parent.updated_at == parent_updated_at &&
      updated_at > parent_updated_at
  end

  def parent_newer?
    linked? &&
      updated_at == parent_updated_at &&
      parent.updated_at > parent_updated_at
  end

  def parent_and_self_newer?
    linked? &&
      parent.updated_at > parent_updated_at &&
      updated_at > parent_updated_at
  end

  def number_of_steps
    steps.count
  end

  def completed_steps
    steps.where(completed: true)
  end

  def first_step_id
    steps.find_by(position: 0)&.id
  end

  def space_taken
    st = 0
    steps.find_each do |step|
      st += step.space_taken
    end
    st
  end

  def make_private(user)
    # Don't update "updated_at" timestamp
    self.record_timestamps = false

    self.added_by = user
    self.published_on = nil
    self.archived_by = nil
    self.archived_on = nil
    self.restored_by = nil
    self.restored_on = nil
    self.protocol_type = Protocol.protocol_types[:in_repository_private]
    result = save

    if result
      Activities::CreateActivityService
        .call(activity_type: :move_protocol_in_repository,
              owner: user,
              subject: self,
              team: team,
              message_items: {
                protocol: id,
                storage: I18n.t('activities.protocols.team_to_my_message')
              })
    end
    result
  end

  # This publish action simply moves the protocol from
  # the private section in the repository into the public
  # section
  def publish(user)
    # Don't update "updated_at" timestamp
    self.record_timestamps = false

    self.added_by = user
    self.published_on = Time.now
    self.archived_by = nil
    self.archived_on = nil
    self.restored_by = nil
    self.restored_on = nil
    self.protocol_type = Protocol.protocol_types[:in_repository_public]
    result = save

    if result
      Activities::CreateActivityService
        .call(activity_type: :move_protocol_in_repository,
              owner: user,
              subject: self,
              team: team,
              message_items: {
                protocol: id,
                storage: I18n.t('activities.protocols.my_to_team_message')
              })
    end
    result
  end

  def archive(user)
    return nil unless can_destroy?

    # Don't update "updated_at" timestamp
    self.record_timestamps = false

    # We keep published_on present, so we know (upon restoring)
    # where the protocol was located

    self.archived_by = user
    self.archived_on = Time.now
    self.restored_by = nil
    self.restored_on = nil
    self.protocol_type = Protocol.protocol_types[:in_repository_archived]
    result = save

    # Update all module protocols that had
    # parent set to this protocol
    if result
      Protocol.where(parent: self).find_each do |p|
        p.update(
          parent: nil,
          parent_updated_at: nil,
          protocol_type: :unlinked
        )
      end

      Activities::CreateActivityService
        .call(activity_type: :archive_protocol_in_repository,
              owner: user,
              subject: self,
              team: team,
              message_items: {
                protocol: id
              })
    end
    result
  end

  def restore(user)
    # Don't update "updated_at" timestamp
    self.record_timestamps = false

    self.archived_by = nil
    self.archived_on = nil
    self.restored_by = user
    self.restored_on = Time.now
    if published_on.present?
      self.published_on = Time.now
      self.protocol_type = Protocol.protocol_types[:in_repository_public]
    else
      self.protocol_type = Protocol.protocol_types[:in_repository_private]
    end
    result = save

    if result
      Activities::CreateActivityService
        .call(activity_type: :restore_protocol_in_repository,
              owner: user,
              subject: self,
              team: team,
              message_items: {
                protocol: id
              })
    end
    result
  end

  def update_keywords(keywords)
    result = true
    begin
      Protocol.transaction do
        self.record_timestamps = false

        # First, destroy all keywords
        protocol_protocol_keywords.destroy_all
        if keywords.present?
          keywords.each do |kw_name|
            kw = ProtocolKeyword.find_or_create_by(name: kw_name, team: team)
            protocol_keywords << kw
          end
        end
      end
    rescue StandardError
      result = false
    end
    result
  end

  def unlink
    self.parent = nil
    self.parent_updated_at = nil
    self.protocol_type = Protocol.protocol_types[:unlinked]
    save!
  end

  def update_parent(current_user)
    ActiveRecord::Base.no_touching do
      # First, destroy parent's step contents
      parent.destroy_contents
      parent.reload

      # Now, clone step contents
      Protocol.clone_contents(self, parent, current_user, false)
    end

    # Lastly, update the metadata
    parent.reload
    parent.record_timestamps = false
    parent.updated_at = updated_at
    parent.save!
    self.record_timestamps = false
    self.parent_updated_at = updated_at
    save!
  end

  def update_from_parent(current_user)
    ActiveRecord::Base.no_touching do
      # First, destroy step contents
      destroy_contents

      # Now, clone parent's step contents
      Protocol.clone_contents(parent, self, current_user, false)
    end

    # Lastly, update the metadata
    reload
    self.record_timestamps = false
    self.updated_at = parent.updated_at
    self.parent_updated_at = parent.updated_at
    self.added_by = current_user
    save!
  end

  def load_from_repository(source, current_user)
    ActiveRecord::Base.no_touching do
      # First, destroy step contents
      destroy_contents

      # Now, clone source's step contents
      Protocol.clone_contents(source, self, current_user, false)
    end

    # Lastly, update the metadata
    reload
    self.name = source.name
    self.record_timestamps = false
    self.updated_at = source.updated_at
    self.parent = source
    self.parent_updated_at = source.updated_at
    self.added_by = current_user
    self.protocol_type = Protocol.protocol_types[:linked]
    save!
  end

  def copy_to_repository(new_name, new_protocol_type, link_protocols, current_user)
    clone = Protocol.new(
      name: new_name,
      description: description,
      protocol_type: new_protocol_type,
      added_by: current_user,
      team: team
    )
    clone.published_on = Time.now if clone.in_repository_public?

    # Don't proceed further if clone is invalid
    return clone if clone.invalid?

    ActiveRecord::Base.no_touching do
      # Okay, clone seems to be valid: let's clone it
      clone = deep_clone(clone, current_user)

      # If the above operation went well, update published_on
      # timestamp
      clone.update(published_on: Time.zone.now) if clone.in_repository_public?
    end

    # Link protocols if neccesary
    if link_protocols
      reload
      self.name = clone.name
      self.record_timestamps = false
      self.added_by = current_user
      self.parent = clone
      ts = clone.updated_at
      self.parent_updated_at = ts
      self.updated_at = ts
      self.protocol_type = Protocol.protocol_types[:linked]
      save!
    end

    clone
  end

  def deep_clone_my_module(my_module, current_user)
    clone = Protocol.new_blank_for_module(my_module)
    clone.name = name
    clone.authors = authors
    clone.description = description
    clone.protocol_type = protocol_type

    if linked?
      clone.added_by = current_user
      clone.parent = parent
      clone.parent_updated_at = parent_updated_at
    end

    deep_clone(clone, current_user)
  end

  def deep_clone_repository(current_user)
    clone = Protocol.new(
      name: name,
      authors: authors,
      description: description,
      added_by: current_user,
      team: team,
      protocol_type: protocol_type,
      published_on: in_repository_public? ? Time.now : nil
    )

    cloned = deep_clone(clone, current_user)

    if cloned
      Activities::CreateActivityService
        .call(activity_type: :copy_protocol_in_repository,
             owner: current_user,
             subject: self,
             team: team,
             project: nil,
             message_items: {
               protocol_new: clone.id,
               protocol_original: id
             })
    end

    cloned
  end

  def destroy_contents
    # Calculate total space taken by the protocol
    st = space_taken
    steps.order(position: :desc).each do |step|
      step.step_orderable_elements.delete_all
      step.destroy!
    end

    # Release space taken by the step
    team.release_space(st)
    team.save

    # Reload protocol
    reload
  end

  def can_destroy?
    steps.map(&:can_destroy?).all?
  end

  def add_team_users_as_viewers!(assigned_by)
    viewer_role = UserRole.find_predefined_viewer_role
    team.user_assignments.where.not(user: assigned_by).find_each do |user_assignment|
      new_user_assignment = UserAssignment.find_or_initialize_by(user: user_assignment.user, assignable: self)
      new_user_assignment.user_role = viewer_role
      new_user_assignment.assigned_by = assigned_by
      new_user_assignment.assigned = :automatically
      new_user_assignment.save!
    end
  end

  private

  def update_user_assignments
    case protocol_type
    when 'in_repository_public'
      assigned_by = protocol_type_was == 'in_repository_archived' && restored_by || added_by
      add_team_users_as_viewers!(assigned_by)
    when 'in_repository_private', 'in_repository_archived'
      automatic_user_assignments.where.not(user: added_by).destroy_all
    end
  end

  def deep_clone(clone, current_user)
    # Save cloned protocol first
    success = clone.save

    # Rename protocol if needed
    unless success
      rename_record(clone, :name)
      success = clone.save
    end

    raise ActiveRecord::RecordNotSaved unless success

    Protocol.clone_contents(self, clone, current_user, true, true)

    clone.reload
    clone
  end

  def update_linked_children
    # Increment/decrement the parent's nr of linked children
    if saved_change_to_parent_id?
      unless parent_id_before_last_save.nil?
        p = Protocol.find_by_id(parent_id_before_last_save)
        p.record_timestamps = false
        p.decrement!(:nr_of_linked_children)
      end
      unless parent_id.nil?
        parent.record_timestamps = false
        parent.increment!(:nr_of_linked_children)
      end
    end
  end

  def decrement_linked_children
    parent.decrement!(:nr_of_linked_children) if parent.present?
  end
end
