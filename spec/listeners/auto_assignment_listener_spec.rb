require 'rails_helper'

RSpec.describe AutoAssignmentListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :open, assignee: nil) }

  describe '#message_created' do
    it 'enqueues AssignmentJob for inbox on incoming message in open unassigned conversation' do
      message = create(:message, conversation: conversation, message_type: :incoming, account: account, inbox: inbox)
      event = Events::Base.new('message.created', Time.zone.now, message: message)

      expect(AutoAssignment::AssignmentJob).to receive(:enqueue_for_inbox).with(inbox.id)

      listener.message_created(event)
    end

    it 'does not enqueue AssignmentJob for outgoing message' do
      message = create(:message, conversation: conversation, message_type: :outgoing, account: account, inbox: inbox)
      event = Events::Base.new('message.created', Time.zone.now, message: message)

      expect(AutoAssignment::AssignmentJob).not_to receive(:enqueue_for_inbox)

      listener.message_created(event)
    end

    it 'does not enqueue AssignmentJob when conversation is already assigned' do
      agent = create(:user, account: account)
      assigned_conversation = create(:conversation, account: account, inbox: inbox, status: :open, assignee: agent)
      message = create(:message, conversation: assigned_conversation, message_type: :incoming, account: account, inbox: inbox)
      event = Events::Base.new('message.created', Time.zone.now, message: message)

      expect(AutoAssignment::AssignmentJob).not_to receive(:enqueue_for_inbox)

      listener.message_created(event)
    end
  end
end
