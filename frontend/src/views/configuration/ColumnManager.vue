<template>
  <div class="is-relative">
    <b-loading :active="isLoading" :is-full-page="false"></b-loading>
    <column-table v-if="mergedColumns.length > 0" :columns="mergedColumns"
                  @column-changed="onColumnChanged"
                  @select-all="onSelectAll"
                  @deselect-all="onDeselectAll"/>
  </div>
</template>

<script>
import CRUDService from '@/services/CRUDService';
import { getErrorMessageAsHtml } from '@/helpers';
import ColumnTable from './ColumnTable.vue';

export default {
  name: 'ColumnManager',
  components: {
    ColumnTable,
  },
  props: {
    schema: { type: Object, default: () => {} },
    table: { type: Object, default: () => {} },
  },
  data() {
    return {
      columns: [],
      dbColumns: [],
      mergedColumns: [],
      isLoading: false,
    };
  },
  methods: {
    mergeColumns() {
      // build a map from db columns with column names as keys
      // and column as value, extended by required fields
      const dbColumnsMap = new Map();
      this.dbColumns.forEach((column) => {
        const fields = {
          table_id: this.table.id,
          info: 'TODO',
          yn_log_insert: 'N',
          yn_log_update: 'N',
          yn_log_delete: 'N',
        };
        dbColumnsMap.set(column.name, { ...column, ...fields });
      });
      // enrich/merge the map column values with currently existing trixx column data
      this.columns.forEach((column) => {
        if (dbColumnsMap.has(column.name)) {
          const current = dbColumnsMap.get(column.name);
          dbColumnsMap.set(column.name, { ...current, ...column });
        } else {
          // console.warn(`The configured column ` +
          //   `${this.schema.name}.${this.table.name}.${column.name} `+
          //   `does not seem to exist in the DB anymore`);
        }
      });

      this.mergedColumns = Array.from(dbColumnsMap.values()).sort((a, b) => {
        const aName = a.name.toUpperCase();
        const bName = b.name.toUpperCase();
        if (aName < bName) { return -1; }
        if (aName > bName) { return 1; }
        return 0;
      });
    },
    async onColumnChanged(column) {
      try {
        this.isLoading = true;
        if (column.id) { // update
          await CRUDService.columns.update(column.id, { column });
        } else { // create
          await CRUDService.columns.create({ column });
        }
        this.$buefy.toast.open({
          message: `Saved changes to column '${column.name}'!`,
          type: 'is-success',
        });
        await this.reload(this.table);
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      } finally {
        this.isLoading = false;
      }
    },
    async reload(table) {
      try {
        this.isLoading = true;
        this.dbColumns = await CRUDService.dbColumns.getAll({
          table_name: table.name,
          schema_name: this.schema.name,
        });
        this.columns = await CRUDService.columns.getAll({ table_id: table.id });
        this.mergeColumns();
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e, 'An error occurred while loading columns!'),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      } finally {
        this.isLoading = false;
      }
    },
    async onSelectAll(type) {
      try {
        this.isLoading = true;
        await CRUDService.columns.selectAll({ table_id: this.table.id, operation: type });
        await this.reload(this.table);
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      } finally {
        this.isLoading = false;
      }
    },
    async onDeselectAll(type) {
      try {
        this.isLoading = true;
        await CRUDService.columns.deselectAll({ table_id: this.table.id, operation: type });
        await this.reload(this.table);
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      } finally {
        this.isLoading = false;
      }
    },
  },
  watch: {
    async table(newTable) {
      if (newTable) {
        await this.reload(newTable);
      } else {
        this.columns = [];
        this.dbColumns = [];
        this.mergedColumns = [];
      }
    },
  },
};
</script>
