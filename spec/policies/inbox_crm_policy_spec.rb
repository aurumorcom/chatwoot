require 'rails_helper'

RSpec.describe InboxCrmPolicy do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:policy) { described_class.new(inbox: inbox, account: account) }

  describe '#allow_email_processing?' do
    context 'when personal_inbox_enabled is false' do
      it 'returns true for any email address' do
        expect(policy.allow_email_processing?('unknown@example.com')).to be true
      end
    end

    context 'when personal_inbox_enabled is true' do
      before do
        inbox.update(personal_inbox_enabled: true)
      end

      it 'returns true when folder is Leads regardless of contact existence' do
        expect(policy.allow_email_processing?('unknown@example.com', folder: 'Leads')).to be true
      end

      it 'returns false for unknown email address' do
        expect(policy.allow_email_processing?('unknown@example.com')).to be false
      end

      it 'returns true for existing contact email' do
        create(:contact, account: account, email: 'known@example.com')
        expect(policy.allow_email_processing?('known@example.com')).to be true
      end

      it 'returns false for blank email address' do
        expect(policy.allow_email_processing?('')).to be false
      end
    end
  end
end
