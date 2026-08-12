class AddPersonalInboxEnabledToInboxes < ActiveRecord::Migration[7.1]
  def change
    add_column :inboxes, :personal_inbox_enabled, :boolean, default: false
  end
end
