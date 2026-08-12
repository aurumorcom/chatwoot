class InboxCrmPolicy
  pattr_initialize [:inbox!, :account!]

  def allow_email_processing?(email_address, folder: nil)
    return true unless inbox.personal_inbox_enabled?
    return true if folder.to_s.casecmp('leads').zero?
    return false if email_address.blank?

    account.contacts.exists?(email: email_address.to_s.downcase.strip)
  end
end
