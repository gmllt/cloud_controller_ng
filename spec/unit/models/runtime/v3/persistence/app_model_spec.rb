require 'spec_helper'

module VCAP::CloudController
  RSpec.describe AppModel do
    let(:app_model) { AppModel.create(space: space, name: 'some-name') }
    let(:space) { Space.make }

    describe '#staging_in_progress' do
      context 'when a build is in staging state' do
        let!(:build) { BuildModel.make(app_guid: app_model.guid, state: BuildModel::STAGING_STATE) }

        it 'returns true' do
          expect(app_model.staging_in_progress?).to eq(true)
        end
      end

      context 'when a build is not in neither pending or staging state' do
        let!(:build) { BuildModel.make(app_guid: app_model.guid, state: BuildModel::STAGED_STATE) }

        it 'returns false' do
          expect(app_model.staging_in_progress?).to eq(false)
        end
      end
    end

    describe 'fields' do
      describe 'max_task_sequence_id' do
        it 'defaults to 0' do
          expect(app_model.max_task_sequence_id).to eq(1)
        end
      end
    end

    describe '#destroy' do
      context 'when the app has buildpack_lifecycle_data' do
        subject(:lifecycle_data) do
          BuildpackLifecycleDataModel.create(buildpacks: ['http://some-buildpack.com', 'http://another-buildpack.net'])
        end

        it 'destroys the buildpack_lifecycle_data and associated buildpack_lifecycle_buildpacks' do
          app_model.update(buildpack_lifecycle_data: lifecycle_data)
          expect {
            app_model.destroy
          }.to change { BuildpackLifecycleDataModel.count }.by(-1).
            and change { BuildpackLifecycleBuildpackModel.count }.by(-2)
        end
      end
    end

    describe 'validations' do
      it { is_expected.to strip_whitespace :name }

      describe 'name' do
        let(:space_guid) { space.guid }
        let(:app) { AppModel.make }

        it 'uniqueness is case insensitive' do
          AppModel.make(name: 'lowercase', space_guid: space_guid)

          expect {
            AppModel.make(name: 'lowerCase', space_guid: space_guid)
          }.to raise_error(Sequel::ValidationFailed, 'name must be unique in space')
        end

        it 'should allow standard ascii characters' do
          app.name = "A -_- word 2!?()\'\"&+."
          expect {
            app.save
          }.to_not raise_error
        end

        it 'should allow backslash characters' do
          app.name = 'a \\ word'
          expect {
            app.save
          }.to_not raise_error
        end

        it 'should allow unicode characters' do
          app.name = '防御力¡'
          expect {
            app.save
          }.to_not raise_error
        end

        it 'should not allow newline characters' do
          app.name = "a \n word"
          expect {
            app.save
          }.to raise_error(Sequel::ValidationFailed)
        end

        it 'should not allow escape characters' do
          app.name = "a \e word"
          expect {
            app.save
          }.to raise_error(Sequel::ValidationFailed)
        end
      end

      describe 'name is unique within a space' do
        it 'name can be reused in different spaces' do
          name = 'zach'

          space1 = Space.make
          space2 = Space.make

          AppModel.make(name: name, space_guid: space1.guid)
          expect {
            AppModel.make(name: name, space_guid: space2.guid)
          }.not_to raise_error
        end

        it 'name is unique in the same space' do
          name = 'zach'

          space = Space.make

          AppModel.make(name: name, space_guid: space.guid)

          expect {
            AppModel.make(name: name, space_guid: space.guid)
          }.to raise_error(Sequel::ValidationFailed, 'name must be unique in space')
        end
      end

      describe 'environment_variables' do
        it 'validates them' do
          expect {
            AppModel.make(environment_variables: '')
          }.to raise_error(Sequel::ValidationFailed, /must be a hash/)
        end
      end

      describe 'droplet' do
        let(:droplet) { DropletModel.make(app: app_model) }

        it 'does not allow droplets that are not STAGED' do
          states = DropletModel::DROPLET_STATES - [DropletModel::STAGED_STATE]
          states.each do |state|
            droplet.state = state
            expect {
              app_model.droplet = droplet
              app_model.save
            }.to raise_error(Sequel::ValidationFailed, /must be in staged state/)
          end
        end

        it 'is valid with droplets that are STAGED' do
          droplet.state = DropletModel::STAGED_STATE
          app_model.droplet = droplet
          expect(app_model).to be_valid
        end
      end
    end

    describe '#lifecycle_type' do
      context 'the model contains buildpack_lifecycle_data' do
        before { BuildpackLifecycleDataModel.make(app: app_model) }

        it 'returns the string "buildpack" if buildpack_lifecycle_data is on the model' do
          expect(app_model.lifecycle_type).to eq('buildpack')
        end
      end

      context 'the model does not contain buildpack_lifecycle_data' do
        before do
          app_model.buildpack_lifecycle_data = nil
          app_model.save
        end

        it 'returns the string "docker" if buildpack_lifecycle data is not on the model' do
          expect(app_model.lifecycle_type).to eq('docker')
        end
      end
    end

    describe '#lifecycle_data' do
      let!(:lifecycle_data) { BuildpackLifecycleDataModel.make(app: app_model) }

      it 'returns buildpack_lifecycle_data if it is on the model' do
        expect(app_model.lifecycle_data).to eq(lifecycle_data)
      end

      it 'is a persistable hash' do
        expect(app_model.reload.lifecycle_data.buildpacks).to eq(lifecycle_data.buildpacks)
        expect(app_model.reload.lifecycle_data.stack).to eq(lifecycle_data.stack)
      end

      context 'buildpack_lifecycle_data is nil' do
        let(:non_buildpack_app_model) { AppModel.create(name: 'non-buildpack', space: space) }

        it 'returns a docker data model' do
          expect(non_buildpack_app_model.lifecycle_data).to be_a(DockerLifecycleDataModel)
        end
      end
    end

    describe '#database_uri' do
      let(:parent_app) { AppModel.make(environment_variables: { 'jesse' => 'awesome' }, space: space) }
      let(:process) { ProcessModel.make(app: parent_app) }

      context 'when there are database-like services' do
        before do
          sql_service_plan     = ServicePlan.make(service: Service.make(label: 'elephantsql-n/a'))
          sql_service_instance = ManagedServiceInstance.make(space: space, service_plan: sql_service_plan, name: 'elephantsql-vip-uat')
          ServiceBinding.make(app: parent_app, service_instance: sql_service_instance, credentials: { 'uri' => 'mysql://foo.com' })

          banana_service_plan     = ServicePlan.make(service: Service.make(label: 'chiquita-n/a'))
          banana_service_instance = ManagedServiceInstance.make(space: space, service_plan: banana_service_plan, name: 'chiqiuta-yummy')
          ServiceBinding.make(app: parent_app, service_instance: banana_service_instance, credentials: { 'uri' => 'banana://yum.com' })
        end

        it 'returns database uri' do
          expect(process.reload.database_uri).to eq('mysql2://foo.com')
        end
      end

      context 'when there are non-database-like services' do
        before do
          banana_service_plan     = ServicePlan.make(service: Service.make(label: 'chiquita-n/a'))
          banana_service_instance = ManagedServiceInstance.make(space: space, service_plan: banana_service_plan, name: 'chiqiuta-yummy')
          ServiceBinding.make(app: parent_app, service_instance: banana_service_instance, credentials: { 'uri' => 'banana://yum.com' })

          uncredentialed_service_plan     = ServicePlan.make(service: Service.make(label: 'mysterious-n/a'))
          uncredentialed_service_instance = ManagedServiceInstance.make(space: space, service_plan: uncredentialed_service_plan, name: 'mysterious-mystery')
          ServiceBinding.make(app: parent_app, service_instance: uncredentialed_service_instance, credentials: {})
        end

        it 'returns nil' do
          expect(process.reload.database_uri).to be_nil
        end
      end

      context 'when there are no services' do
        it 'returns nil' do
          expect(process.reload.database_uri).to be_nil
        end
      end

      context 'when the service binding credentials is nil' do
        before do
          banana_service_plan     = ServicePlan.make(service: Service.make(label: 'chiquita-n/a'))
          banana_service_instance = ManagedServiceInstance.make(space: space, service_plan: banana_service_plan, name: 'chiqiuta-yummy')
          ServiceBinding.make(app: parent_app, service_instance: banana_service_instance, credentials: nil)
        end

        it 'returns nil' do
          expect(process.reload.database_uri).to be_nil
        end
      end
    end

    describe 'before_save' do
      describe 'default enable_ssh' do
        context 'when enable_ssh is set explicitly' do
          it 'does not overwrite it with the default' do
            app1 = AppModel.make(enable_ssh: true)
            expect(app1.enable_ssh).to eq(true)

            app2 = AppModel.make(enable_ssh: false)
            expect(app2.enable_ssh).to eq(false)
          end
        end

        context 'when default_app_ssh_access is true' do
          before do
            TestConfig.override({ default_app_ssh_access: true })
          end

          it 'sets enable_ssh to true' do
            app = AppModel.make
            expect(app.enable_ssh).to eq(true)
          end
        end

        context 'when default_app_ssh_access is false' do
          before do
            TestConfig.override({ default_app_ssh_access: false })
          end

          it 'sets enable_ssh to false' do
            app = AppModel.make
            expect(app.enable_ssh).to eq(false)
          end
        end
      end

      describe 'updating process version' do
        let(:parent_app) { AppModel.make(enable_ssh: false) }
        let!(:process1) { ProcessModelFactory.make(app: parent_app) }
        let!(:process2) { ProcessModelFactory.make(app: parent_app, type: 'astroboy') }

        context 'when enable_ssh has changed' do
          it 'sets a new version for all processes' do
            expect {
              parent_app.update(enable_ssh: true)
            }.to change { [process1.reload.version, process2.reload.version] }
          end
        end

        context 'when enable_ssh has NOT changed' do
          it 'does not update the process versions' do
            expect {
              parent_app.update(enable_ssh: false)
            }.not_to change { [process1.reload.version, process2.reload.version] }
          end
        end
      end
    end

    describe '#user_visibility_filter' do
      let!(:other_app) { AppModel.make }

      context "when a user is a developer in the app's space" do
        let(:user) { make_developer_for_space(app_model.space) }

        it 'the service binding is visible' do
          expect(AppModel.user_visible(user).all).to eq [app_model]
        end
      end

      context "when a user is an auditor in the app's space" do
        let(:user) { make_auditor_for_space(app_model.space) }

        it 'the service binding is visible' do
          expect(AppModel.user_visible(user).all).to eq [app_model]
        end
      end

      context "when a user is an org manager in the app's space" do
        let(:user) { make_manager_for_org(app_model.space.organization) }

        it 'the service binding is visible' do
          expect(AppModel.user_visible(user).all).to eq [app_model]
        end
      end

      context "when a user is a space manager in the app's space" do
        let(:user) { make_manager_for_space(app_model.space) }

        it 'the service binding is visible' do
          expect(AppModel.user_visible(user).all).to eq [app_model]
        end
      end

      context "when a user has no visibility to the app's space" do
        let(:user) { User.make }

        it 'the service binding is not visible' do
          expect(AppModel.user_visible(user).all).to be_empty
        end
      end
    end
  end
end
