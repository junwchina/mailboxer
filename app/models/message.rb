class Message < Notification
  attr_accessible :attachment

  belongs_to :conversation, :validate => true, :autosave => true
  validates_presence_of :sender

  class_attribute :on_deliver_callback
  protected :on_deliver_callback
  scope :conversation, lambda { |conversation|
    where(:conversation_id => conversation.id)
  }

  mount_uploader :attachment, AttachmentUploader
  
  include Concerns::ConfigurableMailer

  class << self
    #Sets the on deliver callback method.
    def on_deliver(callback_method)
      self.on_deliver_callback = callback_method
    end
  end

  #Delivers a Message. USE NOT RECOMENDED.
  #Use Mailboxer::Models::Message.send_message instead.
  def deliver(reply = false, should_clean = true)
    self.clean if should_clean

    #Receiver receipts
    temp_receipts = self.recipients.map do |r|
      msg_receipt = Receipt.new(:is_read => false, :mailbox_type => "inbox")
      msg_receipt.notification = self
      msg_receipt.receiver = r
      msg_receipt
    end

    #Sender receipt
    sender_receipt = Receipt.new(:is_read => true, :mailbox_type => "sentbox")
    sender_receipt.notification = self
    sender_receipt.receiver = self.sender
    sender_receipt

    # if any error occurs, stop to deliver
    return sender_receipt if !temp_receipts.all?(&:valid?)
    temp_receipts.each(&:save!)

    if Mailboxer.uses_emails
      self.recipients.each do |r|
        email_to = r.send(Mailboxer.email_method,self)
        unless email_to.blank?
          get_mailer.send_email(self,r).deliver
        end
      end
    end

    if reply
      self.conversation.touch
    end

    self.recipients=nil
    self.on_deliver_callback.call(self) unless self.on_deliver_callback.nil?

    return sender_receipt
  end
end
