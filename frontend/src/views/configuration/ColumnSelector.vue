<template>
  <div>
    <column-table :columns="mergedColumns"></column-table>
  </div>
</template>

<script>
import ColumnTable from './ColumnTable.vue';
import CRUDService from '@/services/CRUDService';

export default {
  name: 'ColumnSelector',
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
    };
  },
  computed: {
    mergedColumns() {
      // build a map from db columns with column names as keys
      const dbColumnsMap = new Map();
      this.dbColumns.forEach((column) => {
        dbColumnsMap.set(column.name, column);
      });
      // enrich the map with currently existing trixx column data
      this.columns.forEach((column) => {
        if (dbColumnsMap.has(column.name)) {
          const current = dbColumnsMap.get(column.name);
          dbColumnsMap.set(column.name, { ...current, ...column });
        } else {
          console.warn(`The configured column ${this.schema.name}.${this.table.name}.${column.name} does not seem to exist in the database anymore`);
        }
      });

      return Array.from(dbColumnsMap.values());
    },
  },
  watch: {
    async table(newTable) {
      this.dbColumns = await CRUDService.dbColumns.getAll({
        table_name: newTable.name,
        schema_name: this.schema.name,
      });
      const resp = await CRUDService.columns.getAll({ table_id: newTable.id });
      resp.push({
        id: 1, table_id: 3, name: 'name', info: ' ', yn_log_insert: false, yn_log_update: true, yn_log_delete: false,
      });
      this.columns = resp;
    },
  },
};
</script>
