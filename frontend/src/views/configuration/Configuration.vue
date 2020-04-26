<template>
  <div class="columns is-centered is-6 is-variable">
    <schema-manager class="column is-2 border-right"
                     @schema-selected="onSchemaSelected"></schema-manager>
    <table-manager class="column is-2 border-right"
                   :schema="selectedSchema"
                   @table-selected="onTableSelected"></table-manager>
    <column-manager class="column is-4"
                    :schema="selectedSchema"
                    :table="selectedTable"></column-manager>
  </div>
</template>

<script>
import SchemaManager from './SchemaManager.vue';
import TableManager from './TableManager.vue';
import ColumnManager from './ColumnManager.vue';

export default {
  name: 'configuration',
  components: {
    SchemaManager,
    TableManager,
    ColumnManager,
  },
  data() {
    return {
      selectedSchema: null,
      selectedTable: null,
    };
  },
  methods: {
    onSchemaSelected(schema) {
      this.selectedSchema = schema;
    },
    onTableSelected(table) {
      this.selectedTable = table;
    },
  },
};
</script>

<style lang="scss">
  .border-right {
    border-right: 1px solid lightgray;
  }
</style>
