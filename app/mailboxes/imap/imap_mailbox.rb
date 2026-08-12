class Imap::ImapMailbox
  include MailboxHelper
  include IncomingEmailValidityHelper
  attr_accessor :channel, :account, :inbox, :conversation, :processed_mail

  FALLBACK_CONVERSATION_PATTERN = %r{account/(\d+)/conversation/([a-zA-Z0-9-]+)@}

  def process(mail, channel, folder: nil)
    @inbound_mail = mail
    @channel = channel
    load_account
    load_inbox
    decorate_mail

    Rails.logger.info("Processing Email from: #{@processed_mail.original_sender} : inbox #{@inbox.id} : message_id #{@processed_mail.message_id}")

    # Skip processing email if it belongs to any of the edge cases
    return unless incoming_email_from_valid_email?

    email_to_check = outgoing_email? ? @processed_mail.to&.first : @processed_mail.original_sender
    return unless InboxCrmPolicy.new(inbox: @inbox, account: @account).allow_email_processing?(email_to_check, folder: folder)

    ActiveRecord::Base.transaction do
      find_or_create_contact
      find_or_create_conversation
      create_message
      add_attachments_to_message
    end
  end

  private

  def load_account
    @account = @channel.account
  end

  def load_inbox
    @inbox = @channel.inbox
  end

  def decorate_mail
    @processed_mail = MailPresenter.new(@inbound_mail, @account)
  end

  def find_conversation_by_in_reply_to
    return if in_reply_to.blank?

    message = @inbox.messages.find_by(source_id: in_reply_to)
    if message.nil?
      @inbox.conversations.find_by("additional_attributes->>'in_reply_to' = ?", in_reply_to)
    else
      @inbox.conversations.find(message.conversation_id)
    end
  end

  def find_conversation_by_reference_ids
    return if @inbound_mail.references.blank?

    message = find_message_by_references
    if message.present?
      conversation = @inbox.conversations.find_by(id: message.conversation_id)
      return conversation if conversation.present?
    end

    # FALLBACK_PATTERN use to find a conversation that is started by an agent (no incoming message yet)
    conversation_id = find_conversation_by_references
    @inbox.conversations.find_by(uuid: conversation_id) if conversation_id.present?
  end

  def in_reply_to
    sanitize_mailbox_value(@processed_mail.in_reply_to)
  end

  def find_conversation_by_references
    references.each do |message_id|
      match = FALLBACK_CONVERSATION_PATTERN.match(message_id)

      return match[2] if match.present?
    end
  end

  def find_message_by_references
    message_to_return = nil

    references.each do |message_id|
      message = @inbox.messages.find_by(source_id: message_id)
      message_to_return = message if message.present?
    end
    message_to_return
  end

  def find_or_create_conversation
    @conversation = find_conversation_by_in_reply_to || find_conversation_by_reference_ids || ::Conversation.create!(
      {
        account_id: @account.id,
        inbox_id: @inbox.id,
        contact_id: @contact.id,
        contact_inbox_id: @contact_inbox.id,
        additional_attributes: {
          source: 'email',
          in_reply_to: in_reply_to,
          auto_reply: @processed_mail.auto_reply?,
          mail_subject: sanitize_mailbox_value(@processed_mail.subject),
          initiated_at: {
            timestamp: Time.now.utc
          }
        }
      }
    )
  end

  def find_or_create_contact
    email = outgoing_email? ? @processed_mail.to&.first : original_sender_email
    @contact = @inbox.contacts.from_email(email)
    if @contact.present?
      @contact_inbox = ContactInbox.find_by(inbox: @inbox, contact: @contact)
    else
      create_contact
    end
  end

  def create_contact
    email = outgoing_email? ? @processed_mail.to&.first : original_sender_email
    @contact_inbox = ::ContactInboxWithContactBuilder.new(
      source_id: email,
      inbox: @inbox,
      contact_attributes: {
        name: identify_contact_name,
        email: email,
        additional_attributes: { source_id: "email:#{processed_mail.message_id}" }
      }
    ).perform

    @contact = @contact_inbox.contact
    Rails.logger.info "[MailboxHelper] Contact created with ID: #{@contact.id} for inbox with ID: #{@inbox.id}"
  end

  def identify_contact_name
    if outgoing_email?
      sanitize_mailbox_value(@processed_mail.to&.first&.split('@')&.first)
    else
      sanitize_mailbox_value(processed_mail.sender_name || processed_mail.from.first.split('@').first)
    end
  end

  def create_message
    message_id = sanitize_mailbox_value(processed_mail.message_id)
    return if @conversation.messages.find_by(source_id: message_id).present?

    @message = @conversation.messages.create!(
      account_id: @conversation.account_id,
      sender: outgoing_email? ? find_sender_for_outgoing_message : @conversation.contact,
      content: sanitize_mailbox_value(mail_content)&.truncate(150_000),
      inbox_id: @conversation.inbox_id,
      message_type: outgoing_email? ? 'outgoing' : 'incoming',
      content_type: 'incoming_email',
      source_id: message_id,
      content_attributes: {
        email: processed_mail.serialized_data,
        cc_email: processed_mail.cc,
        bcc_email: processed_mail.bcc
      }
    )
  end

  def find_sender_for_outgoing_message
    @account.users.find_by(email: @channel.email.to_s.downcase)
  end

  def outgoing_email?
    return false if @processed_mail.from.blank? || @channel.email.blank?

    @processed_mail.from.map(&:downcase).include?(@channel.email.downcase)
  end

  def original_sender_email
    sanitize_mailbox_value(@processed_mail.original_sender)
  end

  def references
    sanitize_mailbox_value(Array.wrap(@inbound_mail.references))
  end
end
