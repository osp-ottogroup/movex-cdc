<template>
  <div class="content">
    <h6>Columns</h6>
<!--    <div class="loader-wrapper is-active">-->
<!--      <div class="loader is-loading"></div>-->
<!--    </div>-->
    <column-table :columns="mergedColumns"
                  @column-changed="onColumnChanged"/>
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
      mergedColumns: [],
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

      this.mergedColumns = Array.from(dbColumnsMap.values());
    },
    async onColumnChanged(column) {
      try {
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
        this.$buefy.toast.open({
          message: 'An error occurred!',
          type: 'is-danger',
          duration: 5000,
        });
      }
    },
    async reload(table) {
      try {
        this.dbColumns = await CRUDService.dbColumns.getAll({
          table_name: table.name,
          schema_name: this.schema.name,
        });
        this.columns = await CRUDService.columns.getAll({ table_id: table.id });
        this.mergeColumns();
      } catch (e) {
        this.$buefy.toast.open({
          message: 'An error occurred while loading columns!',
          type: 'is-danger',
          duration: 5000,
        });
      }
    },
  },
  watch: {
    async table(newTable) {
      await this.reload(newTable);
    },
  },
};
</script>

<!--<style lang="scss">-->
<!--.loader-wrapper {-->
<!--  position: absolute;-->
<!--  top: 0;-->
<!--  left: 0;-->
<!--  height: 100%;-->
<!--  width: 100%;-->
<!--  background: #fff;-->
<!--  opacity: 0;-->
<!--  z-index: -1;-->
<!--  transition: opacity .3s;-->
<!--  display: flex;-->
<!--  justify-content: center;-->
<!--  align-items: center;-->
<!--  border-radius: 6px;-->

<!--  .loader {-->
<!--    height: 80px;-->
<!--    width: 80px;-->
<!--  }-->

<!--  &.is-active {-->
<!--    opacity: 1;-->
<!--    z-index: 1;-->
<!--  }-->
<!--}-->
<!--</style>-->
