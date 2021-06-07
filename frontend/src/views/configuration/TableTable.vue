<template>
  <div>
    <b-table :data="tables"
             :selected.sync="selectedTable"
             @click="onTableSelected">
      <b-table-column field="name" label="Observed Tables" searchable>
        <template v-slot:searchable="props">
          <b-input v-model="props.filters[props.column.field]"
                   icon="magnify"
                   size="is-small"/>
        </template>

        <template v-slot="props">
          {{ props.row.name }}
          <b-field v-show="selectedTable && selectedTable.id === props.row.id"
                   grouped
                   class="is-pulled-right">
            <div>
              <b-button icon-right="pencil"
                        class="is-small"
                        @click="onEditClicked()" />
            </div>
            <div>
              <b-tooltip label="Show activity log for this table">
                <b-button icon-right="text-subject" size="is-small" class="ml-1" @click="showActivityLogModal(props.row)"/>
              </b-tooltip>
            </div>
          </b-field>
          <div v-if="props.row.yn_deleted_in_db === 'Y'"
               :class="{'deleted-in-db--margin': selectedTable && selectedTable.id === props.row.id}"
               class="is-size-7 has-text-danger deleted-in-db">
            This table doesn't exist in the database anymore.
            This will lead to errors when generating the triggers.
            It should be removed from observation.
          </div>
        </template>
      </b-table-column>

      <template v-slot:empty>
        <div class="content has-text-grey has-text-centered is-size-7">
          <b-icon icon="information" />
          <p v-if="!schema">Select a schema.</p>
          <p v-else-if="tables.length === 0">Add a table to observe.</p>
          <p v-else>No data found.</p>
        </div>
      </template>
    </b-table>

    <template v-if="activityLogModal.show">
      <ActivityLogModal
        :filter="activityLogModal.filter"
        @close="closeActivityLogModal">
      </ActivityLogModal>
    </template>
  </div>
</template>

<script>
import ActivityLogModal from '@/components/ActivityLogModal.vue';

export default {
  name: 'TableTable',
  props: {
    tables: { type: Array, default: () => [] },
    schema: { type: Object, default: () => {} },
  },
  components: {
    ActivityLogModal,
  },
  data() {
    return {
      selectedTable: null,
      activityLogModal: {
        show: false,
        filter: null,
      },
    };
  },
  methods: {
    onTableSelected(table) {
      this.$emit('table-selected', table);
    },
    onEditClicked() {
      this.$emit('edit-table', this.selectedTable);
    },
    showActivityLogModal(table) {
      this.activityLogModal.filter = {
        schemaName: this.schema.name,
        tableName: table.name,
      };
      this.activityLogModal.show = true;
    },
    closeActivityLogModal() {
      this.activityLogModal.filter = null;
      this.activityLogModal.show = false;
    },
  },
  watch: {
    tables(newList, oldList) {
      if (!newList || newList.length === 0) {
        this.selectedTable = null;
      } else if (newList && newList !== oldList) {
        // eslint-disable-next-line prefer-destructuring
        this.selectedTable = newList[0];
      } else if (newList && newList === oldList && this.selectedTable !== null) {
        // reference of table list has not changed
        // it seems that the selected table has changed, so find changed table
        const newTable = newList.find((table) => table.id === this.selectedTable.id);
        if (newTable !== undefined) {
          this.selectedTable = newTable;
        } else {
          // table was deleted
          this.selectedTable = null;
        }
      }
      this.$emit('table-selected', this.selectedTable);
    },
  },
};
</script>

<style lang="scss" scoped>
.deleted-in-db {
  background-color: white;
  padding: 0.2rem;
  &--margin {
    margin-top: 0.5rem;
  }
}
</style>
