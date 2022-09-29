# frozen_string_literal: true

module UserRolesHelper
  def user_roles_collection
    Rails.cache.fetch([current_user, 'available_user_roles']) do
      @user_roles_collection ||= UserRole.order(id: :asc).pluck(:name, :id)
    end
  end

  def team_user_roles_collection
    team_permissions =
      PermissionExtends::TeamPermissions.constants.map { |const| TeamPermissions.const_get(const) } +
      ProtocolPermissions.constants.map { |const| ProtocolPermissions.const_get(const) } +
      RepositoryPermissions.constants.map { |const| RepositoryPermissions.const_get(const) }
    UserRole.where('permissions && ARRAY[?]::varchar[]', team_permissions)
            .sort_by { |user_role| (user_role.permissions & team_permissions).length }
            .reverse!
  end

  def managing_team_user_roles_collection
    UserRole.where('permissions && ARRAY[?]::varchar[]', [TeamPermissions::USERS_MANAGE])
  end
end
