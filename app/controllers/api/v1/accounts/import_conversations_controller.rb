class Api::V1::Accounts::ImportConversationsController < Api::V1::Accounts::BaseController
  def create
    import_data = params[:import_data]
    return head :unprocessable_entity if import_data.blank?

    ActiveRecord::Base.transaction do
      import_data.each do |data|
        process_conversation(data)
      end
    end

    head :ok
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def process_conversation(data)
    contact = find_or_create_contact(data[:contact], data[:inbox_id], data[:source_id])
    inbox = Current.account.inboxes.find(data[:inbox_id])
    
    conversation = find_or_create_conversation(data[:conversation], inbox, contact, data[:source_id])
    
    if data[:messages].present?
      create_messages(conversation, data[:messages]) 
      update_last_activity(conversation, data[:messages])
    end
  end

  def find_or_create_contact(contact_data, inbox_id, source_id)
    return nil if contact_data.blank?

    # Try to find by email first
    contact = Current.account.contacts.find_by(email: contact_data[:email]) if contact_data[:email].present?
    
    # If not found, try to find by phone
    contact ||= Current.account.contacts.find_by(phone_number: contact_data[:phone_number]) if contact_data[:phone_number].present?

    # If still not found, create new
    contact ||= Current.account.contacts.create!(
      name: contact_data[:name],
      email: contact_data[:email],
      phone_number: contact_data[:phone_number],
      custom_attributes: contact_data[:custom_attributes]
    )

    # Ensure contact inbox exists
    if source_id.present?
      contact_inbox = ContactInbox.find_by(inbox_id: inbox_id, source_id: source_id)
      if contact_inbox.blank?
        ContactInbox.create!(
          contact: contact,
          inbox_id: inbox_id,
          source_id: source_id
        )
      end
    else
      # If no source_id, check if contact_inbox exists for this inbox
      contact_inbox = ContactInbox.find_by(inbox_id: inbox_id, contact_id: contact.id)
      if contact_inbox.blank?
        ContactInbox.create!(
          contact: contact,
          inbox_id: inbox_id,
          source_id: SecureRandom.uuid
        )
      end
    end

    contact
  end

  def find_or_create_conversation(conv_data, inbox, contact, source_id)
    # Check if conversation already exists by external source_id
    if conv_data.dig(:additional_attributes, :source_id).present?
      existing_conversation = Conversation.where(account_id: Current.account.id, inbox_id: inbox.id)
                                          .where("additional_attributes->>'source_id' = ?", conv_data[:additional_attributes][:source_id].to_s)
                                          .first
      return existing_conversation if existing_conversation
    end

    # Determine status (default to resolved if not provided to avoid active inbox clutter)
    status = conv_data[:status] || 'resolved'
    
    # Find contact_inbox
    contact_inbox = if source_id.present?
                      ContactInbox.find_by!(inbox_id: inbox.id, source_id: source_id)
                    else
                      ContactInbox.find_by!(inbox_id: inbox.id, contact_id: contact.id)
                    end

    conversation = Conversation.create!(
      account: Current.account,
      inbox: inbox,
      contact: contact,
      contact_inbox: contact_inbox,
      status: status,
      additional_attributes: conv_data[:additional_attributes] || {}
    )

    # Assign agent if provided
    if conv_data[:assignee_email].present?
      assignee = Current.account.users.find_by(email: conv_data[:assignee_email])
      conversation.update_column(:assignee_id, assignee.id) if assignee
    end

    # Update timestamps
    created_at = conv_data[:created_at].to_datetime
    updates = {
      created_at: created_at,
      updated_at: conv_data[:updated_at] || created_at
    }
    
    # Use update_columns to bypass callbacks/timestamps
    conversation.update_columns(updates)
    
    conversation
  end

  def create_messages(conversation, messages_data)
    # Filter out messages that already exist based on source_id
    incoming_source_ids = messages_data.pluck(:source_id).map(&:to_s).compact
    existing_source_ids = Message.where(conversation_id: conversation.id, source_id: incoming_source_ids).pluck(:source_id)
    
    messages_to_insert = messages_data.reject { |msg| msg[:source_id].present? && existing_source_ids.include?(msg[:source_id].to_s) }.map do |msg_data|
      # Determine sender
      sender = nil
      if msg_data[:message_type] == 'incoming'
        sender = conversation.contact
      elsif msg_data[:sender].present? && msg_data[:sender][:email].present?
        sender = Current.account.users.find_by(email: msg_data[:sender][:email])
      end
      # Fallback to current user if outgoing and no sender specified, or leave nil
      sender ||= Current.user if msg_data[:message_type] == 'outgoing'

      created_at = msg_data[:created_at].to_datetime

      {
        account_id: conversation.account_id,
        inbox_id: conversation.inbox_id,
        conversation_id: conversation.id,
        message_type: Message.message_types[msg_data[:message_type] || 'incoming'],
        content: msg_data[:content],
        content_type: Message.content_types[msg_data[:content_type] || 'text'],
        private: msg_data[:private] || false,
        sender_type: sender&.class&.name,
        sender_id: sender&.id,
        status: Message.statuses['sent'],
        created_at: created_at,
        updated_at: created_at,
        source_id: msg_data[:source_id],
        content_attributes: msg_data[:content_attributes] || {}
      }
    end

    Message.insert_all(messages_to_insert) if messages_to_insert.any?
  end

  def update_last_activity(conversation, messages_data)
    # Find the latest message timestamp
    last_msg_time = messages_data.map { |m| m[:created_at].to_datetime }.max
    
    return unless last_msg_time

    conversation.update_columns(last_activity_at: last_msg_time)
  end
end
