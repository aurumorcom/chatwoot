class AddPersonalInboxToInboxes < ActiveRecord::Migration[7.1]
  def change
    add_column :inboxes, :personal_inbox, :boolean, default: false
  end
end
