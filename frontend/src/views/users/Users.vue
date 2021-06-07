<template>
  <div class="columns is-centered">
    <div class="column is-half">
      <div class="level">
        <div class="level-left">
          <b-button
            type="is-primary"
            @click="showUserModal(null)">
            Create User
          </b-button>
        </div>
        <div class="level-right">
          <b-button
            type="is-info"
            icon-left="magnify"
            @click="onSearchButtonClicked"/>
        </div>
      </div>

      <b-table
        :data="users"
        :loading="isLoading"
        default-sort="last_name"
        striped
        hoverable>
          <b-table-column field="id" label="ID" numeric sortable :searchable="showSearchFields" v-slot="props">
            {{ props.row.id }}
          </b-table-column>
          <b-table-column field="first_name" label="First Name" sortable :searchable="showSearchFields" v-slot="props">
            {{ props.row.first_name }}
          </b-table-column>
          <b-table-column field="last_name" label="Last Name" sortable :searchable="showSearchFields" v-slot="props">
            {{ props.row.last_name }}
          </b-table-column>
          <b-table-column field="email" label="e-Mail" sortable :searchable="showSearchFields" v-slot="props">
            {{ props.row.email }}
          </b-table-column>
          <b-table-column field="db_user" label="DB-User" sortable :searchable="showSearchFields" v-slot="props">
            {{ props.row.db_user }}
          </b-table-column>
          <b-table-column label="Info" width="4rem" v-slot="props">
            <span>
              <b-tooltip label="Admin User">
                <b-icon v-if="props.row.yn_admin === 'Y'" icon="account-circle" size="is-small"/>
              </b-tooltip>
              <b-tooltip label="Account is locked">
                <b-icon v-if="props.row.yn_account_locked === 'Y'" icon="lock" size="is-small"/>
              </b-tooltip>
            </span>
          </b-table-column>
          <b-table-column label="Actions" v-slot="props">
            <b-field grouped>
              <b-tooltip label="Edit the user">
                <b-button icon-right="pencil" size="is-small" @click="showUserModal(props.row)"/>
              </b-tooltip>
              <b-tooltip label="Show user's activity log">
                <b-button icon-right="text-subject" size="is-small" class="ml-1" @click="showActivityLogModal(props.row)"/>
              </b-tooltip>
            </b-field>
          </b-table-column>
      </b-table>
    </div>

    <template v-if="modal.show">
      <user-modal
        :user-id="modal.userId"
        @created="onCreated"
        @saved="onSaved"
        @deleted="onDeleted"
        @close="closeUserModal">
      </user-modal>
    </template>

    <template v-if="activityLogModal.show">
      <ActivityLogModal
        :filter="activityLogModal.filter"
        @close="closeActivityLogModal">
      </ActivityLogModal>
    </template>
  </div>
</template>

<script>
import { getErrorMessageAsHtml } from '@/helpers';
import ActivityLogModal from '@/components/ActivityLogModal.vue';
import CRUDService from '../../services/CRUDService';
import UserModal from './UserModal.vue';

export default {
  name: 'Users',
  components: {
    ActivityLogModal,
    UserModal,
  },
  data() {
    return {
      isLoading: true,
      users: [],
      showSearchFields: false,
      modal: {
        show: false,
        userId: null,
      },
      activityLogModal: {
        show: false,
        filter: null,
      },
    };
  },
  async created() {
    try {
      this.users = await CRUDService.users.getAll();
    } catch (e) {
      this.$buefy.notification.open({
        message: getErrorMessageAsHtml(e, 'An error occurred while loading users!'),
        type: 'is-danger',
        indefinite: true,
        position: 'is-top',
      });
    } finally {
      this.isLoading = false;
    }
  },
  methods: {
    showUserModal(user) {
      this.modal.userId = user ? user.id : null;
      this.modal.show = true;
    },
    closeUserModal() {
      this.modal.userId = null;
      this.modal.show = false;
    },
    showActivityLogModal(user) {
      this.activityLogModal.filter = { userId: user.id };
      this.activityLogModal.show = true;
    },
    closeActivityLogModal() {
      this.activityLogModal.filter = null;
      this.activityLogModal.show = false;
    },
    onSearchButtonClicked() {
      this.showSearchFields = !this.showSearchFields;
    },
    onSaved(savedUser) {
      const index = this.users.findIndex((user) => user.id === savedUser.id);
      this.$set(this.users, index, savedUser);
      this.closeUserModal();
    },
    onDeleted(deletedUser) {
      const index = this.users.findIndex((user) => user.id === deletedUser.id);
      this.users.splice(index, 1);
      this.closeUserModal();
    },
    onCreated(createdUser) {
      this.users.push(createdUser);
      this.closeUserModal();
    },
  },
};
</script>
