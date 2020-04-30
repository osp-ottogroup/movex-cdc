<template>
  <div>
    <b-table ref="table"
             :data="tables"
             :selected.sync="selectedTable"
             @click="onTableSelected">
      <template slot-scope="props">
        <b-table-column field="name" label="Observed Tables">
          {{ props.row.name }}
          <b-button v-show="selectedTable && selectedTable.id === props.row.id"
                    icon-right="pen"
                    class="is-pulled-right is-small"
                    @click="onEditClicked()" />
        </b-table-column>
      </template>

      <template slot="empty">
        <div class="content has-text-grey has-text-centered is-size-7">
          <b-icon icon="info-circle" />
          <p v-if="!schema">Select a schema.</p>
          <p v-else>Add a table to observe.</p>
        </div>
      </template>
    </b-table>
  </div>
</template>

<script>
export default {
  name: 'TableTable',
  props: {
    tables: { type: Array, default: () => [] },
    schema: { type: Object, default: () => {} },
  },
  data() {
    return {
      selectedTable: null,
    };
  },
  methods: {
    onTableSelected(table) {
      this.$emit('table-selected', table);
    },
    onEditClicked() {
      this.$emit('edit-table', this.selectedTable);
    },
  },
};
</script>
