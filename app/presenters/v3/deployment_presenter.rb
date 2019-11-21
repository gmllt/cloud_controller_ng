require 'presenters/v3/base_presenter'
require 'presenters/mixins/metadata_presentation_helpers'

module VCAP::CloudController::Presenters::V3
  class DeploymentPresenter < BasePresenter
    include VCAP::CloudController::Presenters::Mixins::MetadataPresentationHelpers

    def to_hash
      {
        guid: deployment.guid,
        state: deployment.state,
        status: {
          value: deployment.status_value,
          reason: deployment.status_reason,
          details: {
            last_successful_healthcheck: deployment.last_healthy_at
          }
        },
        strategy: deployment.strategy,
        droplet: {
          guid: deployment.droplet_guid
        },
        previous_droplet: {
          guid: deployment.previous_droplet_guid
        },
        new_processes: new_processes,
        created_at: deployment.created_at,
        updated_at: deployment.updated_at,
        relationships: {
          app: {
            data: {
              guid: deployment.app.guid
            }
          }
        },
        metadata: {
          labels: hashified_labels(deployment.labels),
          annotations: hashified_annotations(deployment.annotations),
        },
        links: build_links,
        revision: revision,
      }
    end

    private

    def deployment
      @resource
    end

    def revision
      (deployment.app.revisions_enabled && deployment.revision_guid) ? { guid: deployment.revision_guid, version: deployment.revision_version } : nil
    end

    def new_processes
      deployment.historical_related_processes.map do |drp|
        {
          guid: drp.process_guid,
          type: drp.process_type
        }
      end
    end

    def build_links
      url_builder = VCAP::CloudController::Presenters::ApiUrlBuilder.new

      {
        self: {
          href: url_builder.build_url(path: "/v3/deployments/#{deployment.guid}")
        },
        app: {
          href: url_builder.build_url(path: "/v3/apps/#{deployment.app.guid}")
        },
      }
    end
  end
end
