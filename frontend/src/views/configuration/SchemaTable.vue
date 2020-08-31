<template>
  <div>
    <b-table :data="schemas"
             :selected.sync="selectedSchema"
             @click="onSchemaSelected">
      <b-table-column field="name" label="Schemas" searchable>
        <template v-slot:searchable="props">
          <b-input v-model="props.filters[props.column.field]"
                   icon="magnify"
                   size="is-small"/>
        </template>

        <template v-slot="props">
          {{ props.row.name }}
          <b-button v-show="selectedSchema && selectedSchema.id === props.row.id"
                    icon-right="pencil"
                    class="is-pulled-right is-small"
                    @click="onEditClicked()" />
        </template>
      </b-table-column>

      <template v-slot:empty>
        <div class="content has-text-grey has-text-centered is-size-7">
          <b-icon icon="information" />
          <p v-if="schemas.length === 0">Your user has no authorized schemas.</p>
          <p v-else>No data found.</p>
        </div>
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
  watch: {
    schemas(newList, oldList) {
      if (newList && newList !== oldList && newList.length > 0) {
        // eslint-disable-next-line prefer-destructuring
        this.selectedSchema = newList[0];
        this.$emit('schema-selected', this.selectedSchema);
      }
    },
  },
};
</script>
