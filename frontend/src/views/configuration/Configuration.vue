<template>
  <div class="columns is-centered">
    <schema-selector class="column is-2"
                     @schema-selected="onSchemaSelected"></schema-selector>
    <table-selector class="column is-2"
                    :schema="selectedSchema"
                    @table-selected="onTableSelected"></table-selector>
    <column-selector class="column is-4"
                     :schema="selectedSchema"
                     :table="selectedTable"></column-selector>
  </div>
</template>

<script>
import SchemaSelector from './SchemaSelector.vue';
import TableSelector from './TableSelector.vue';
import ColumnSelector from './ColumnSelector.vue';

export default {
  name: 'configuration',
  components: {
    SchemaSelector,
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
