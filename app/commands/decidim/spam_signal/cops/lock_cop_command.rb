# frozen_string_literal: true

module Decidim
  module SpamSignal
    module Cops
      class LockCopCommand < CopHandler
        def self.form
          ::Decidim::SpamSignal::Cops::LockSettingsForm
        end

        def call
          errors.add(
            :base,
            I18n.t("errors.spam",
              scope: "decidim.spam_signal",
              default: "this looks like spam."
            )
          )
          unless suspicious_user.access_locked?
            sinalize! if config["sinalize_user_enabled"]
            hide_comment! if config["hide_comments_enabled"]
            lock!
          end
        end

        private
          def hide_comment!
            suspicious_comments ||= Decidim::Comments::Comment.where(author: suspicious_user)
            suspicious_comments.each do |spam|
              Decidim::Admin::HideResource.call(spam, admin_reporter)
            end
          end

          def sinalize!
            moderation = Decidim::UserModeration.find_or_create_by!(user: suspicious_user)
            Decidim::UserReport.find_or_create_by!(moderation: moderation)  do |report|
              report.moderation = moderation
              report.user = admin_reporter
              report.reason = "spam"
              report.details = I18n.t("decidim.spam_signal.spam_signal_justification")
            end
          end

          def lock!
            suspicious_user.lock_access!(
              send_instructions: true
            )
            suspicious_user.save!(validate: false)
          end
      end
    end
  end
end
