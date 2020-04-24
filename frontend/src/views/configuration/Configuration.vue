<template>
  <div class="columns is-centered">
    <schema-manager class="column is-3"
                     @schema-selected="onSchemaSelected"></schema-manager>
    <table-selector class="column is-2"
                    :schema="selectedSchema"
                    @table-selected="onTableSelected"></table-selector>
    <column-selector class="column is-4"
                     :schema="selectedSchema"
                     :table="selectedTable"></column-selector>
  </div>
</template>

<script>
import SchemaManager from './SchemaManager.vue';
import TableSelector from './TableSelector.vue';
import ColumnSelector from './ColumnSelector.vue';

export default {
  name: 'configuration',
  components: {
    SchemaManager,
    TableSelector,
    ColumnSelector,
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
