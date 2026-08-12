class AutoAssignmentListener < BaseListener
  def message_created(event)
    message, _account = extract_message_and_account(event)
    return unless message.incoming?

    conversation = message.conversation
    return unless conversation.open? && conversation.assignee_id.blank?

    AutoAssignment::AssignmentJob.enqueue_for_inbox(conversation.inbox_id)
  end
end
