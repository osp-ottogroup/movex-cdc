<template>
  <div class="modal" :class="{'is-active': isActive}">
    <div class="modal-background"
         @click="onClose"/>
    <div class="modal-card" style="width: auto">
      <header class="modal-card-head">
        <p class="modal-card-title">Add Table</p>
        <button class="delete"
                aria-label="close"
                @click="onClose">
        </button>
      </header>
      <section class="modal-card-body">
        <b-field label="Table">
          <b-select v-model="table.name"
                    placeholder="Select a table"
                    expanded>
            <option v-for="table in tables" :key="table.id" :value="table.name">
              {{ table.name }}
            </option>
          </b-select>
        </b-field>

        <b-field label="Topic">
          <b-input placeholder="Enter Topic"
                   v-model="table.topic">
          </b-input>
        </b-field>
      </section>
      <footer class="modal-card-foot">
        <button class="button is-primary"
                @click="onAddButtonClicked">
          Add
        </button>
      </footer>
    </div>
  </div>
</template>

<script>
export default {
  name: 'TableModal',
  props: {
    tables: { type: Array, default: () => [] },
    isActive: { type: Boolean, default: false },
  },
  data() {
    return {
      table: {
        name: null,
        topic: null,
      },
    };
  },
  methods: {
    onClose() {
      this.resetData();
      this.$emit('update:is-active', false);
    },
    onAddButtonClicked() {
      this.resetData();
      this.$emit('add-table', this.table);
    },
    resetData() {
      this.table.name = null;
      this.table.topic = null;
    },
  },
};
</script>

<style lang="scss" scoped>
  footer button {
    margin-left: auto;
  }
</style>
