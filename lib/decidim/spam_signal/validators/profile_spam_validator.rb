# frozen_string_literal: true

module Decidim
  module SpamSignal
    module ProfileSpamValidator
      extend ActiveSupport::Concern

      included do
        validate :scan_spam
        def scan_spam
          return if !about || about.empty?
          return if blocked_at_changed?(from: nil) # we are blocking the user, don't validate if it is spam.
          current_user = self
          tested_content = Extractors::ProfileExtractor.extract(self, spam_config)

          # Collect fired symbols
          symboles = spam_scanners.map do |scan_command, scan_option|
            scan_command.call(
              tested_content,
              scan_option
            )
          end.map(&:keys).flatten.filter { |s| s != :ok && s != :valid }
          return if !symboles || symboles.empty?

          # Check the rules
          suspicious_rules = spam_ruleset("suspicious")
          spam_rules = spam_ruleset("spam")
          fire_suspicious_cop = suspicious_rules.map do |ruleset|
            ruleset.map do |rule|
              symboles.include? rule
            end.all?
          end.any?
          fire_spam_cop = spam_rules.map do |ruleset|
            ruleset.map do |rule|
              symboles.include? rule
            end.all?
          end.any?

          # If it's a cop fire it, else if it's a suspicous, fire it.
          if fire_spam_cop && obvious_spam_cop
            obvious_spam_cop.call(
              errors: errors,
              error_key: :about,
              suspicious_user: current_user,
              config: obvious_spam_cop_options,
              justification: "profile: " + tested_content
            ) do |on|
              on(:save) {}
              on(:restore_value) { restore_values(current_user) }
            end
          elsif fire_suspicious_cop && suspicious_spam_cop
            suspicious_spam_cop.call(
              errors: errors,
              error_key: :about,
              suspicious_user: current_user,
              config: suspicious_spam_cop_options,
              justification:  "profile: " + tested_content
            ) do |on|
              on(:save) {}
              on(:restore_value) { restore_values(current_user) }
            end
          end
        end

        # Case the lock cop is there,
        # it will save the user without validation,
        # we should then update the attributes to before
        # state
        def restore_values(user)
          user.about = user.about_was
          user.personal_url = user.personal_url_was
        end

        def obvious_spam_cop_options
          cop = spam_config.profiles.spam_cop
          return nil unless cop
          cop
        end

        def scan_context
          {
            validator: "profile",
            is_updating: true,
            date: updated_at,
            current_organization: organization,
            author: self
          }
        end

        def obvious_spam_cop
          cop_key = obvious_spam_cop_options["handler_name"]
          return nil unless cop_key
          Cops::CopsRepository.instance.strategy(
            cop_key
          )
        end

        def suspicious_spam_cop_options
          cop = spam_config.profiles.suspicious_cop
          return nil unless cop
          cop
        end

        def suspicious_spam_cop
          cop_key = suspicious_spam_cop_options["handler_name"]
          return nil unless cop_key
          Cops::CopsRepository.instance.strategy(
            cop_key
          )
        end

        def spam_config
          @config ||= Config.get_config(organization)
        end

        def spam_scanners
          spam_config.profiles.scans.map do |s, options|
            options["context"] = scan_context
            [Scans::ScansRepository.instance.strategy(s), options]
          end
        end

        def spam_ruleset(handler_name = "spam")
          spam_config.profiles.rules.map do |rule_id, rule|
            rule
          end.filter { |r| r["handler_name"] == handler_name }.map do |r|
            r["rules"].symbolize_keys.keys
          end
        end
      end
    end
  end
end
