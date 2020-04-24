<template>
  <div>
    <b-table ref="table"
             :data="schemas"
             :selected.sync="selectedSchema"
             @click="onSchemaSelected">
      <template slot-scope="props">
        <b-table-column field="name" label="Schemas">
          {{ props.row.name }}
          <b-button v-show="selectedSchema && selectedSchema.id === props.row.id"
                    icon-right="pen"
                    class="is-pulled-right is-small"
                    @click="onEditClicked()" />
        </b-table-column>
      </template>
    </b-table>
  </div>
</template>

<script>
export default {
  name: 'SchemaTable',
  props: {
    schemas: { type: Array, default: () => [] },
  },
  data() {
    return {
      selectedSchema: null,
    };
  },
  methods: {
    onSchemaSelected(schema) {
      this.$emit('schema-selected', schema);
    },
    onEditClicked() {
      this.$emit('edit-schema', this.selectedSchema);
    },
  },
};
</script>
