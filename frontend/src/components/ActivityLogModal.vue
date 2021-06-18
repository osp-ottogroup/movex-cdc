<template>
  <b-modal :active="true"
           width="90vw"
           has-modal-card
           trap-focus
           aria-role="dialog"
           aria-modal
           @close="onClose">
    <div class="modal-card" :style="`width: ${activityLog.length === 0 ? '30vw' : '80vw'}`">
      <header class="modal-card-head">
        <p class="modal-card-title">Activity Log</p>
        <button class="delete"
                aria-label="close"
                @click="onClose">
        </button>
      </header>
      <section class="modal-card-body">
        <div v-if="!isLoading" class="mb-3">
          <span class="title is-6">Filter:</span>
          <span class="subtitle is-6 ml-2">{{filterMessage}}</span>
        </div>
        <div v-if="!isLoading && activityLog.length === 0">No entries found</div>
        <div v-if="!isLoading && activityLog.length > 0">
          <b-table
            ref="activityLogTable"
            :data="activityLog"
            default-sort="created_at"
            default-sort-direction="desc"
            striped
            hoverable
            detailed
            :show-detail-icon="true">
            <b-table-column field="user_id" label="User-ID" numeric v-slot="props">
              {{ props.row.user_id }}
            </b-table-column>
            <b-table-column field="client_ip" label="Client IP" sortable v-slot="props">
              {{ props.row.client_ip }}
            </b-table-column>
            <b-table-column field="schema_name" label="Schema Name" sortable v-slot="props">
              {{ props.row.schema_name }}
            </b-table-column>
            <b-table-column field="table_name" label="Table Name" sortable v-slot="props">
              {{ props.row.table_name }}
            </b-table-column>
            <b-table-column field="column_name" label="Column Name" sortable v-slot="props">
              {{ props.row.column_name }}
            </b-table-column>
            <b-table-column field="action" label="Action" cell-class="no-wrap" v-slot="props">
              <div>{{ props.row.action.substring(0, 40) }} ...</div>
              <div class="has-text-info-dark pointer"
                   @click="props.toggleDetails(props.row)">
                {{ $refs.activityLogTable.isVisibleDetailRow(props.row) ? 'less ...' : 'more ...'}}
              </div>
            </b-table-column>
            <b-table-column field="created_at" label="Timestamp" sortable v-slot="props">
              {{ new Date(props.row.created_at).toLocaleString() }}
            </b-table-column>

            <template #detail="props">
              {{ props.row.action }}
            </template>
          </b-table>
        </div>

        <b-loading :active="isLoading" :is-full-page="false"/>

      </section>
      <footer class="modal-card-foot is-justify-content-flex-end">
        <b-button type="is-primary"
                  @click="onCloseButtonClicked">
          Close
        </b-button>
      </footer>
    </div>
  </b-modal>
</template>

<script>
import { getErrorMessageAsHtml } from '@/helpers';
import CRUDService from '../services/CRUDService';

export default {
  name: 'ActivityLogModal',
  props: {
    filter: { type: Object, default: () => {} },
  },
  async created() {
    try {
      const filterParams = {};
      if (this.filter.userId) filterParams.user_id = this.filter.userId;
      if (this.filter.schemaName) filterParams.schema_name = this.filter.schemaName;
      if (this.filter.tableName) filterParams.table_name = this.filter.tableName;
      if (this.filter.columnName) filterParams.column_name = this.filter.columnName;
      this.activityLog = await CRUDService.activityLog.get(filterParams);
    } catch (e) {
      this.$buefy.notification.open({
        message: getErrorMessageAsHtml(e, 'An error occurred while loading the activity log!'),
        type: 'is-danger',
        indefinite: true,
        position: 'is-top',
      });
    } finally {
      this.isLoading = false;
    }
  },
  data() {
    return {
      isLoading: true,
      activityLog: [],
    };
  },
  computed: {
    filterMessage() {
      const messages = [];
      if (this.filter.userId) messages.push(`User-ID=${this.filter.userId}`);
      if (this.filter.schemaName) messages.push(`Schema=${this.filter.schemaName}`);
      if (this.filter.tableName) messages.push(`Table=${this.filter.tableName}`);
      if (this.filter.columnName) messages.push(`Column=${this.filter.columnName}`);
      return messages.join(', ');
    },
  },
  methods: {
    onClose() {
      this.$emit('close');
    },
    onCloseButtonClicked() {
      this.$emit('close');
    },
  },
};
</script>

<style lang="scss" scoped>
.modal-card {
  min-width: 30vw;
  min-height: 30vh;
}
::v-deep .no-wrap {
  white-space: nowrap;
}
.pointer {
  cursor: pointer;
}
</style>
