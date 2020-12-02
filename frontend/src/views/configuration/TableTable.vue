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
          <b-button v-show="selectedTable && selectedTable.id === props.row.id"
                    icon-right="pencil"
                    class="is-pulled-right is-small"
                    @click="onEditClicked()" />
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
